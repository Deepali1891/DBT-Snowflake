-- Analysis: monthly revenue summary
-- Run with: dbt compile --select analyses/monthly_revenue_summary
-- Then execute the compiled SQL directly in Snowflake.

select
    date_trunc('month', order_date)   as order_month,
    customer_country,
    product_category,
    count(order_id)                   as total_orders,
    sum(total_price)                  as total_revenue,
    avg(total_price)                  as avg_order_value
from {{ ref('fct_orders') }}
where status = 'delivered'
group by 1, 2, 3
order by 1 desc, total_revenue desc
