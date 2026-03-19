with source as (
    select
        "c1" as order_id,
        "c2" as order_item_id,
        "c3" as product_id,
        "c4" as seller_id,
        "c5" as shipping_limit_date,
        "c6" as price,
        "c7" as freight_value
    from {{ source('bronze', 'raw_order_items') }}
),
deduped as (
    select *,
        row_number() over (partition by order_id, order_item_id order by shipping_limit_date desc) as row_num
    from source
    where order_id is not null
      and order_item_id is not null
),
enriched as (
    select
        d.order_id,
        d.order_item_id,
        d.product_id,
        d.seller_id,
        cast(d.shipping_limit_date as timestamp_ntz) as shipping_limit_date,
        cast(d.price as decimal(10,2))               as price,
        cast(d.freight_value as decimal(10,2))       as freight_value,
        p.product_category
    from deduped d
    left join {{ ref('stg_products') }} p
        on d.product_id = p.product_id
    where d.row_num = 1
      and d.price > 0
)
select * from enriched
