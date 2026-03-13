with source as (
    select * from {{ source('bronze', 'raw_customers') }}
),
cleaned as (
    select
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix as zip_code,
        case 
            when lower(customer_city) = 'sao paulo' then 'São Paulo'
            when lower(customer_city) = 'rio de janeiro' then 'Rio de Janeiro'
            when lower(customer_city) = 'belo horizonte' then 'Belo Horizonte'
            when lower(customer_city) = 'brasilia' then 'Brasília'
            when lower(customer_city) = 'curitiba' then 'Curitiba'
            when lower(customer_city) = 'campinas' then 'Campinas'
            when lower(customer_city) = 'porto alegre' then 'Porto Alegre'
            when lower(customer_city) = 'salvador' then 'Salvador'
            when lower(customer_city) = 'guarulhos' then 'Guarulhos'
            when lower(customer_city) = 'sao bernardo do campo' then 'São Bernardo do Campo'
            else initcap(customer_city)
        end as city,
        upper(customer_state) as state_code
    from source
)
select * from cleaned