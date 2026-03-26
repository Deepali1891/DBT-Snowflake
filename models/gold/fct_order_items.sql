with order_items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp
    from {{ ref('stg_orders') }}
),

-- flag orders that contain exactly one line item (used in experience mart)
order_item_counts as (
    select
        order_id,
        count(*) as item_count
    from {{ ref('stg_order_items') }}
    group by order_id
)

select
    {{ generate_surrogate_key(['oi.order_id', 'oi.order_item_id']) }}  as order_item_sk,
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp                                      as order_date,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value                                     as total_item_value,
    oi.product_category,
    case when oic.item_count = 1 then true else false end           as is_single_item_order

from order_items oi
left join orders            o   on oi.order_id = o.order_id
left join order_item_counts oic on oi.order_id = oic.order_id
