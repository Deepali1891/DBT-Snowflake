-- Silver layer: staged orders
-- Cleans and standardises raw order data from the bronze layer.
-- Converts cents to dollars, trims strings, and casts data types.

with source as (

    select * from {{ source('bronze', 'raw_orders') }}

),

staged as (

    select
        order_id,
        customer_id,
        product_id,
        cast(order_date as date)                            as order_date,
        quantity,
        unit_price_cents,
        {{ cents_to_dollars('unit_price_cents') }}          as unit_price,
        quantity * unit_price_cents                         as total_price_cents,
        {{ cents_to_dollars('quantity * unit_price_cents') }} as total_price,
        lower(trim(status))                                 as status,
        cast(created_at as timestamp_ntz)                   as created_at,
        cast(updated_at as timestamp_ntz)                   as updated_at
    from source

)

select * from staged
