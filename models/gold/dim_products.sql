-- Gold layer: product dimension
-- Enriches product records with sales metrics for use in reporting and analytics.

with products as (

    select * from {{ ref('stg_products') }}

),

orders as (

    select * from {{ ref('stg_orders') }}
    where status not in ('cancelled')

),

product_sales_summary as (

    select
        product_id,
        sum(quantity)    as total_units_sold,
        sum(total_price) as total_revenue
    from orders
    group by 1

),

final as (

    select
        p.product_id,
        p.product_name,
        p.category,
        p.subcategory,
        p.unit_price,
        p.is_active,
        coalesce(s.total_units_sold, 0) as total_units_sold,
        coalesce(s.total_revenue, 0)    as total_revenue,
        p.created_at,
        p.updated_at
    from products p
    left join product_sales_summary s using (product_id)

)

select * from final
