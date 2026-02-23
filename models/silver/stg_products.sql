-- Silver layer: staged products
-- Cleans and standardises raw product data from the bronze layer.
-- Converts price from cents to dollars, normalises strings, and casts types.

with source as (

    select * from {{ source('bronze', 'raw_products') }}

),

staged as (

    select
        product_id,
        {{ clean_string('product_name') }}              as product_name,
        {{ clean_string('category') }}                  as category,
        {{ clean_string('subcategory') }}               as subcategory,
        unit_price_cents,
        {{ cents_to_dollars('unit_price_cents') }}      as unit_price,
        cast(is_active as boolean)                      as is_active,
        cast(created_at as timestamp_ntz)               as created_at,
        cast(updated_at as timestamp_ntz)               as updated_at
    from source

)

select * from staged
