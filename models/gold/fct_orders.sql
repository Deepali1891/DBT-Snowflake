with orders as (
    select * from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
),

items_agg as (
    select
        order_id,
        count(*)                        as total_items,
        sum(price)                      as total_price,
        sum(freight_value)              as total_freight,
        sum(price + freight_value)      as total_revenue
    from {{ ref('stg_order_items') }}
    group by order_id
),

-- highest-priced item determines the primary category of the order
primary_category as (
    select order_id, product_category
    from {{ ref('stg_order_items') }}
    qualify row_number() over (partition by order_id order by price desc) = 1
),

payments_agg as (
    select
        order_id,
        sum(payment_value)              as total_payment_value,
        max(payment_installments)       as max_installments
    from {{ ref('stg_payments') }}
    group by order_id
),

-- most-used payment type per order
payment_type_mode as (
    select order_id, payment_type
    from (
        select order_id, payment_type, count(*) as cnt
        from {{ ref('stg_payments') }}
        group by order_id, payment_type
    )
    qualify row_number() over (partition by order_id order by cnt desc) = 1
),

reviews_agg as (
    select
        order_id,
        avg(review_score)               as avg_satisfaction_score,
        count(*)                        as review_count
    from {{ ref('stg_order_reviews') }}
    group by order_id
),

order_item_counts as (
    select order_id, count(*) as item_count
    from {{ ref('stg_order_items') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.city                                          as customer_city,
    c.state_code                                    as customer_state_code,
    'Brazil'                                        as customer_country,
    o.order_status                                  as status,
    o.order_purchase_timestamp                      as order_date,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    coalesce(ia.total_items, 0)                     as total_items,
    coalesce(ia.total_price, 0)                     as total_price,
    coalesce(ia.total_freight, 0)                   as total_freight,
    coalesce(ia.total_revenue, 0)                   as total_revenue,
    coalesce(pa.total_payment_value, 0)             as total_payment_value,
    ptm.payment_type,
    pa.max_installments,
    ra.avg_satisfaction_score,
    coalesce(ra.review_count, 0)                    as review_count,
    pc.product_category,
    case when o.order_status = 'delivered' then true else false end      as is_delivered,
    datediff(
        'day',
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
    )                                               as delivery_days,
    case
        when o.order_delivered_customer_date  is not null
             and o.order_estimated_delivery_date is not null
             and o.order_delivered_customer_date <= o.order_estimated_delivery_date
        then true
        when o.order_delivered_customer_date  is not null
             and o.order_estimated_delivery_date is not null
        then false
    end                                             as is_on_time,
    case when oic.item_count = 1 then true else false end               as is_single_item_order

from orders o
left join customers         c   on o.customer_id  = c.customer_id
left join items_agg         ia  on o.order_id     = ia.order_id
left join primary_category  pc  on o.order_id     = pc.order_id
left join payments_agg      pa  on o.order_id     = pa.order_id
left join payment_type_mode ptm on o.order_id     = ptm.order_id
left join reviews_agg       ra  on o.order_id     = ra.order_id
left join order_item_counts oic on o.order_id     = oic.order_id
