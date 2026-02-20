-- Silver layer: staged customers
-- Cleans and standardises raw customer data from the bronze layer.
-- Trims whitespace, normalises casing, and casts timestamps.

with source as (

    select * from {{ source('bronze', 'raw_customers') }}

),

staged as (

    select
        customer_id,
        {{ clean_string('first_name') }}  as first_name,
        {{ clean_string('last_name') }}   as last_name,
        lower(trim(email))                as email,
        trim(phone)                       as phone,
        {{ clean_string('country') }}     as country,
        {{ clean_string('city') }}        as city,
        cast(created_at as timestamp_ntz) as created_at,
        cast(updated_at as timestamp_ntz) as updated_at
    from source

)

select * from staged
