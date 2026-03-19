with source as (
    select
        "c1" as order_id,
        "c2" as payment_sequential,
        "c3" as payment_type,
        "c4" as payment_installments,
        "c5" as payment_value
    from {{ source('bronze', 'raw_order_payments') }}
),
deduped as (
    select *,
        row_number() over (partition by order_id, payment_sequential order by payment_value desc) as row_num
    from source
    where order_id is not null
),
cleaned as (
    select
        order_id,
        payment_sequential,
        coalesce(lower(trim(payment_type)), 'unknown') as payment_type,
        cast(payment_installments as integer)          as payment_installments,
        cast(payment_value as decimal(10,2))           as payment_value
    from deduped
    where row_num = 1
      and payment_value > 0
)
select * from cleaned
