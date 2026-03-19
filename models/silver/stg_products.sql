with products as (
    select
        "c1" as product_id,
        "c2" as product_category_name,
        "c3" as product_name_length,
        "c4" as product_description_length,
        "c5" as product_photos_qty,
        "c6" as product_weight_g,
        "c7" as product_length_cm,
        "c8" as product_height_cm,
        "c9" as product_width_cm
    from {{ source('bronze', 'raw_products') }}
),
translations as (
    select
        "c1" as product_category_name,
        "c2" as product_category_name_english
    from {{ source('bronze', 'raw_product_category_name_translation') }}
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
