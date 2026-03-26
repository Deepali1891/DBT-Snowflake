with delivered_orders as (
    select order_id, customer_id, order_purchase_timestamp
    from {{ ref('stg_orders') }}
    where order_status = 'delivered'
),

customers as (
    select customer_id, customer_unique_id
    from {{ ref('stg_customers') }}
),

order_items as (
    select * from {{ ref('stg_order_items') }}
),

-- one row per product × unique customer (delivered orders only)
product_buyers as (
    select
        oi.product_id,
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    from order_items oi
    inner join delivered_orders o on oi.order_id   = o.order_id
    inner join customers        c on o.customer_id = c.customer_id
),

buyer_order_counts as (
    select
        product_id,
        customer_unique_id,
        count(distinct order_id)            as orders_for_product,
        min(order_purchase_timestamp)       as first_purchase,
        max(order_purchase_timestamp)       as last_purchase
    from product_buyers
    group by product_id, customer_unique_id
),

buyer_stats as (
    select
        product_id,
        count(distinct customer_unique_id)                              as total_unique_buyers,
        count(distinct case when orders_for_product > 1
                            then customer_unique_id end)               as repeat_buyers
    from buyer_order_counts
    group by product_id
),

-- avg days from first to last purchase for repeat buyers
repeat_timing as (
    select
        product_id,
        avg(datediff('day', first_purchase, last_purchase))            as avg_days_between_purchases
    from buyer_order_counts
    where orders_for_product > 1
    group by product_id
),

-- "new buyer" = customer whose very first delivered order contained this product
customer_first_order as (
    select
        c.customer_unique_id,
        min(o.order_purchase_timestamp)                                as first_order_date
    from delivered_orders o
    inner join customers c on o.customer_id = c.customer_id
    group by c.customer_unique_id
),

new_buyer_stats as (
    select
        oi.product_id,
        count(distinct c.customer_unique_id)                           as new_buyers,
        avg(oi.price + oi.freight_value)                               as avg_new_buyer_item_value
    from order_items oi
    inner join delivered_orders    o   on oi.order_id         = o.order_id
    inner join customers           c   on o.customer_id       = c.customer_id
    inner join customer_first_order cfo on c.customer_unique_id = cfo.customer_unique_id
    where o.order_purchase_timestamp = cfo.first_order_date
    group by oi.product_id
),

-- how many distinct sellers carry each product
seller_counts as (
    select product_id, count(distinct seller_id) as seller_count
    from order_items
    group by product_id
)

select
    bs.product_id,
    dp.product_category,
    dp.price_tier,
    bs.total_unique_buyers,
    bs.repeat_buyers,
    case
        when bs.total_unique_buyers > 0
        then round(bs.repeat_buyers / bs.total_unique_buyers::float, 4)
    end                                                                 as repeat_purchase_rate,
    rt.avg_days_between_purchases,
    coalesce(nb.new_buyers, 0)                                         as new_buyers,
    nb.avg_new_buyer_item_value,
    sc.seller_count

from buyer_stats bs
left join {{ ref('dim_products') }} dp  on bs.product_id = dp.product_id
left join repeat_timing             rt  on bs.product_id = rt.product_id
left join new_buyer_stats           nb  on bs.product_id = nb.product_id
left join seller_counts             sc  on bs.product_id = sc.product_id
