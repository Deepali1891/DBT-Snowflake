-- Grain: one row per product × calendar month
-- Cohorts every product on its own timeline (months_since_market_entry)
-- so products can be compared at equivalent points in their lifecycle,
-- regardless of when they entered the market.

with delivered_items as (
    select
        oi.product_id,
        oi.order_id,
        oi.price + oi.freight_value                                     as total_item_value,
        o.order_purchase_timestamp
    from {{ ref('stg_order_items') }} oi
    inner join {{ ref('stg_orders') }} o on oi.order_id = o.order_id
    where o.order_status = 'delivered'
),

market_entry as (
    select
        product_id,
        date_trunc('month', min(order_purchase_timestamp))::date        as market_entry_month
    from delivered_items
    group by product_id
),

cohort_agg as (
    select
        di.product_id,
        date_trunc('month', di.order_purchase_timestamp)::date          as calendar_month,
        count(distinct di.order_id)                                     as orders_count,
        count(*)                                                        as units_sold,
        sum(di.total_item_value)                                        as revenue
    from delivered_items di
    group by di.product_id, date_trunc('month', di.order_purchase_timestamp)::date
),

with_running_totals as (
    select
        ca.product_id,
        ca.calendar_month,
        me.market_entry_month,
        datediff('month', me.market_entry_month, ca.calendar_month)     as months_since_market_entry,
        ca.orders_count,
        ca.units_sold,
        ca.revenue,
        sum(ca.revenue) over (
            partition by ca.product_id
            order by ca.calendar_month
            rows between unbounded preceding and current row
        )                                                               as cumulative_revenue,
        lag(ca.revenue) over (
            partition by ca.product_id
            order by ca.calendar_month
        )                                                               as prev_month_revenue
    from cohort_agg ca
    inner join market_entry me on ca.product_id = me.product_id
)

select
    wrt.product_id,
    dp.product_category,
    dp.price_tier,
    wrt.market_entry_month,
    wrt.months_since_market_entry,
    wrt.calendar_month,
    wrt.orders_count,
    wrt.units_sold,
    wrt.revenue,
    wrt.cumulative_revenue,
    case
        when wrt.prev_month_revenue > 0
        then round(
            (wrt.revenue - wrt.prev_month_revenue) / wrt.prev_month_revenue * 100,
            2
        )
    end                                                                 as mom_revenue_pct_change

from with_running_totals wrt
left join {{ ref('dim_products') }} dp on wrt.product_id = dp.product_id
