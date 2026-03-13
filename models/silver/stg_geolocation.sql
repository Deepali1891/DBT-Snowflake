with source as (
    select * from {{ source('bronze', 'raw_geolocation') }}
),
cleaned as (
    select
        cast(geolocation_zip_code_prefix as varchar) as zip_code,
        avg(geolocation_lat)                         as latitude,
        avg(geolocation_lng)                         as longitude,
        case
            when lower(geolocation_city) = 'sao paulo' then 'São Paulo'
            when lower(geolocation_city) = 'rio de janeiro' then 'Rio de Janeiro'
            when lower(geolocation_city) = 'belo horizonte' then 'Belo Horizonte'
            when lower(geolocation_city) = 'brasilia' then 'Brasília'
            when lower(geolocation_city) = 'curitiba' then 'Curitiba'
            when lower(geolocation_city) = 'campinas' then 'Campinas'
            when lower(geolocation_city) = 'porto alegre' then 'Porto Alegre'
            when lower(geolocation_city) = 'salvador' then 'Salvador'
            when lower(geolocation_city) = 'guarulhos' then 'Guarulhos'
            when lower(geolocation_city) = 'sao bernardo do campo' then 'São Bernardo do Campo'
            else initcap(geolocation_city)
        end                      as city,
        upper(geolocation_state) as state_code
    from source
    where geolocation_zip_code_prefix is not null
    group by geolocation_zip_code_prefix, geolocation_city, geolocation_state
)
select * from cleaned
