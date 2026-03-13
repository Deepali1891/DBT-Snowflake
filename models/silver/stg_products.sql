with products as (
    select * from {{ source('bronze', 'raw_products') }}
),
translations as (
    select * from {{ source('bronze', 'raw_product_category_name_translation') }}
),
cleaned as (
    select
        p.product_id,
        coalesce(t.product_category_name_english, 'uncategorized') as product_category,
        cast(p.product_name_length as integer)                      as product_name_length,
        cast(p.product_description_length as integer)               as product_description_length,
        cast(p.product_photos_qty as integer)                       as product_photos_qty,
        cast(p.product_weight_g as integer)                         as product_weight_g,
        cast(p.product_length_cm as integer)                        as product_length_cm,
        cast(p.product_height_cm as integer)                        as product_height_cm,
        cast(p.product_width_cm as integer)                         as product_width_cm
    from products p
    left join translations t
        on p.product_category_name = t.product_category_name
    where p.product_id is not null
      and p.product_weight_g > 0
)
select * from cleaned
