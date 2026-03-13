with source as (
    select * from {{ source('bronze', 'raw_sellers') }}
),
cleaned as (
    select
        seller_id,
        cast(seller_zip_code_prefix as varchar) as zip_code,
        case
            when lower(seller_city) = 'sao paulo' then 'São Paulo'
            when lower(seller_city) = 'rio de janeiro' then 'Rio de Janeiro'
            when lower(seller_city) = 'belo horizonte' then 'Belo Horizonte'
            when lower(seller_city) = 'brasilia' then 'Brasília'
            when lower(seller_city) = 'curitiba' then 'Curitiba'
            when lower(seller_city) = 'campinas' then 'Campinas'
            when lower(seller_city) = 'porto alegre' then 'Porto Alegre'
            when lower(seller_city) = 'salvador' then 'Salvador'
            when lower(seller_city) = 'guarulhos' then 'Guarulhos'
            when lower(seller_city) = 'sao bernardo do campo' then 'São Bernardo do Campo'
            else initcap(seller_city)
        end                   as city,
        upper(seller_state)   as state_code
    from source
    where seller_id is not null
)
select * from cleaned
