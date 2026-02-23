-- Gold layer: customer dimension
-- Enriches customer records with order metrics for use in reporting and analytics.

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customer_order_summary as (

    select
        customer_id,
        min(order_date)     as first_order_date,
        max(order_date)     as most_recent_order_date,
        count(order_id)     as number_of_orders,
        sum(total_price)    as lifetime_value
    from orders
    group by 1

),

final as (

    select
        c.customer_id,
        c.first_name,
        c.last_name,
        c.first_name || ' ' || c.last_name  as full_name,
        c.email,
        c.phone,
        c.country,
        c.city,
        s.first_order_date,
        s.most_recent_order_date,
        coalesce(s.number_of_orders, 0)          as number_of_orders,
        coalesce(s.lifetime_value, 0)            as lifetime_value,
        c.created_at,
        c.updated_at
    from customers c
    left join customer_order_summary s using (customer_id)

)

select * from final
