with delivered_items as (
    select
        oi.product_id,
        oi.order_id,
        oi.price + oi.freight_value                                     as item_revenue,
        o.order_purchase_timestamp
    from {{ ref('stg_order_items') }} oi
    inner join {{ ref('stg_orders') }} o on oi.order_id = o.order_id
    where o.order_status = 'delivered'
),

-- market_entry_date = first time this product was sold (delivered)
product_dates as (
    select
        product_id,
        min(order_purchase_timestamp)                                   as market_entry_date,
        max(order_purchase_timestamp)                                   as last_sale_date
    from delivered_items
    group by product_id
),

sales_with_offset as (
    select
        di.product_id,
        di.order_id,
        di.item_revenue,
        di.order_purchase_timestamp,
        pd.market_entry_date,
        pd.last_sale_date,
        datediff('month', pd.market_entry_date, di.order_purchase_timestamp) as months_since_entry
    from delivered_items di
    inner join product_dates pd on di.product_id = pd.product_id
),

period_stats as (
    select
        product_id,
        count(case when months_since_entry between 0 and 2  then 1 end) as units_m1_m3,
        count(case when months_since_entry between 3 and 5  then 1 end) as units_m4_m6,
        count(case when months_since_entry between 6 and 11 then 1 end) as units_m7_m12,
        count(case when months_since_entry >= 12            then 1 end) as units_m13_plus,
        sum(case when months_since_entry between 0 and 2    then item_revenue end) as revenue_m1_m3,
        sum(case when months_since_entry between 3 and 5    then item_revenue end) as revenue_m4_m6,
        sum(case when months_since_entry between 6 and 11   then item_revenue end) as revenue_m7_m12,
        sum(case when months_since_entry >= 12              then item_revenue end) as revenue_m13_plus
    from sales_with_offset
    group by product_id
),

-- recent trend: last 3 months vs prior 3 months relative to last_sale_date
trend_stats as (
    select
        product_id,
        count(case
            when datediff('month', order_purchase_timestamp, last_sale_date) < 3
            then 1 end)                                                 as recent_3m_units,
        count(case
            when datediff('month', order_purchase_timestamp, last_sale_date) between 3 and 5
            then 1 end)                                                 as prior_3m_units
    from sales_with_offset
    group by product_id
),

-- month offset of highest sales volume
peak_month as (
    select product_id, months_since_entry as peak_sales_month_offset
    from (
        select product_id, months_since_entry, count(*) as units
        from sales_with_offset
        group by product_id, months_since_entry
    )
    qualify row_number() over (partition by product_id order by units desc) = 1
)

select
    pd.product_id,
    dp.product_category,
    dp.price_tier,
    pd.market_entry_date,
    pd.last_sale_date,
    datediff('month', pd.market_entry_date, pd.last_sale_date) + 1     as active_selling_months,
    coalesce(ps.units_m1_m3,      0)                                   as units_m1_m3,
    coalesce(ps.units_m4_m6,      0)                                   as units_m4_m6,
    coalesce(ps.units_m7_m12,     0)                                   as units_m7_m12,
    coalesce(ps.units_m13_plus,   0)                                   as units_m13_plus,
    coalesce(ps.revenue_m1_m3,    0)                                   as revenue_m1_m3,
    coalesce(ps.revenue_m4_m6,    0)                                   as revenue_m4_m6,
    coalesce(ps.revenue_m7_m12,   0)                                   as revenue_m7_m12,
    coalesce(ps.revenue_m13_plus, 0)                                   as revenue_m13_plus,
    pm.peak_sales_month_offset,
    coalesce(ts.recent_3m_units,  0)                                   as recent_3m_units,
    coalesce(ts.prior_3m_units,   0)                                   as prior_3m_units,
    case
        when coalesce(ts.recent_3m_units, 0) > coalesce(ts.prior_3m_units, 0) * 1.1
            then 'Growing'
        when coalesce(ts.prior_3m_units, 0) > 0
             and coalesce(ts.recent_3m_units, 0) < coalesce(ts.prior_3m_units, 0) * 0.9
            then 'Declining'
        else 'Stable'
    end                                                                 as recent_trend,
    case
        -- Shooting Star: strong entry (>10 units m1-m3) then sharp drop (<30%)
        when coalesce(ps.units_m1_m3, 0) > 10
             and coalesce(ps.units_m4_m6, 0) < coalesce(ps.units_m1_m3, 0) * 0.3
            then 'Shooting Star'
        -- Long-term Classic: 12+ months active and not declining
        when datediff('month', pd.market_entry_date, pd.last_sale_date) >= 12
             and coalesce(ts.recent_3m_units, 0) >= coalesce(ts.prior_3m_units, 0) * 0.9
            then 'Long-term Classic'
        -- Steady Performer: 6+ months, m4-m6 >= 50% of m1-m3 (consistent)
        when datediff('month', pd.market_entry_date, pd.last_sale_date) >= 6
             and coalesce(ps.units_m4_m6, 0) >= coalesce(ps.units_m1_m3, 0) * 0.5
            then 'Steady Performer'
        -- Fading: declining but has prior activity
        when coalesce(ts.prior_3m_units, 0) > 0
             and coalesce(ts.recent_3m_units, 0) < coalesce(ts.prior_3m_units, 0) * 0.9
            then 'Fading'
        -- Niche: low total volume (≤5 delivered units ever)
        when coalesce(ps.units_m1_m3, 0) + coalesce(ps.units_m4_m6, 0)
           + coalesce(ps.units_m7_m12, 0) + coalesce(ps.units_m13_plus, 0) <= 5
            then 'Niche'
        else 'Emerging'
    end                                                                 as lifecycle_classification

from product_dates pd
left join {{ ref('dim_products') }} dp on pd.product_id = dp.product_id
left join period_stats              ps on pd.product_id = ps.product_id
left join trend_stats               ts on pd.product_id = ts.product_id
left join peak_month                pm on pd.product_id = pm.product_id
