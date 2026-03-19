with products as (
    select * from {{ ref('stg_products') }}
),

-- average selling price per product (from all order items, all statuses)
product_avg_prices as (
    select
        product_id,
        avg(price) as avg_price
    from {{ ref('stg_order_items') }}
    group by product_id
),

combined as (
    select
        p.product_id,
        p.product_category,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        p.product_photos_qty,
        p.product_name_length,
        p.product_description_length,
        coalesce(pap.avg_price, 0)      as avg_price
    from products p
    left join product_avg_prices pap on p.product_id = pap.product_id
)

select
    product_id,
    product_category,
    avg_price,
    -- price tier: ntile(3) within category so Budget/Mid-range/Premium are
    -- always relative to peers in the same category, not the whole catalog
    case
        when avg_price = 0 then 'Unknown'
        else case ntile(3) over (partition by product_category order by avg_price)
            when 1 then 'Budget'
            when 2 then 'Mid-range'
            when 3 then 'Premium'
        end
    end                                 as price_tier,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    product_photos_qty,
    product_name_length,
    product_description_length

from combined
