-- Gold layer: customer orders mart
-- Aggregates order data at the customer level for business reporting.
-- Provides revenue, order count, and average order value per customer.

with orders as (

    select * from {{ ref('fct_orders') }}

),

aggregated as (

    select
        customer_id,
        customer_name,
        customer_email,
        customer_country,
        count(order_id)                                             as total_orders,
        count(case when status = 'delivered' then 1 end)           as delivered_orders,
        count(case when status = 'cancelled' then 1 end)           as cancelled_orders,
        sum(case when status != 'cancelled' then total_price end)  as total_revenue,
        min(order_date)                                             as first_order_date,
        max(order_date)                                             as last_order_date,
        {{ safe_divide('sum(case when status != \'cancelled\' then total_price end)',
                       'count(case when status != \'cancelled\' then 1 end)') }} as avg_order_value
    from orders
    group by 1, 2, 3, 4

)

select * from aggregated
