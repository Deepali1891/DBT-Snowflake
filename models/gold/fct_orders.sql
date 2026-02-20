-- Gold layer: orders fact table
-- Joins order data with customer and product dimensions.
-- This is the central fact table for order-level analysis.

with orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select
        customer_id,
        full_name       as customer_name,
        email           as customer_email,
        country         as customer_country
    from {{ ref('dim_customers') }}

),

products as (

    select
        product_id,
        product_name,
        category        as product_category,
        subcategory     as product_subcategory
    from {{ ref('dim_products') }}

),

final as (

    select
        o.order_id,
        o.customer_id,
        c.customer_name,
        c.customer_email,
        c.customer_country,
        o.product_id,
        p.product_name,
        p.product_category,
        p.product_subcategory,
        o.order_date,
        o.quantity,
        o.unit_price,
        o.total_price,
        o.status,
        o.created_at,
        o.updated_at
    from orders o
    left join customers c using (customer_id)
    left join products  p using (product_id)

)

select * from final
