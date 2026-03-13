with source as (
    select * from {{ source('bronze', 'raw_orders') }}
),
deduped as (
    select *,
        row_number() over (partition by order_id order by order_purchase_timestamp desc) as row_num
    from source
    where order_id is not null
),
cleaned as (
    select
        order_id,
        customer_id,
        lower(trim(order_status))                            as order_status,
        cast(order_purchase_timestamp as timestamp_ntz)      as order_purchase_timestamp,
        cast(order_approved_at as timestamp_ntz)             as order_approved_at,
        cast(order_delivered_carrier_date as timestamp_ntz)  as order_delivered_carrier_date,
        cast(order_delivered_customer_date as timestamp_ntz) as order_delivered_customer_date,
        cast(order_estimated_delivery_date as timestamp_ntz) as order_estimated_delivery_date
    from deduped
    where row_num = 1
      and order_purchase_timestamp <= current_timestamp
)
select * from cleaned
