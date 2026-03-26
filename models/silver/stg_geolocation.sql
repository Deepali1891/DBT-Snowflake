with source as (
    select
        "c1" as geolocation_zip_code_prefix,
        "c2" as geolocation_lat,
        "c3" as geolocation_lng,
        "c4" as geolocation_city,
        "c5" as geolocation_state
    from {{ source('bronze', 'raw_geolocation') }}
),
cleaned as (
    select
        cast(geolocation_zip_code_prefix as varchar) as zip_code,
        avg(geolocation_lat)                         as latitude,
        avg(geolocation_lng)                         as longitude,
        any_value(case
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
        end)                     as city,
        any_value(upper(geolocation_state)) as state_code
    from source
    where geolocation_zip_code_prefix is not null
    group by geolocation_zip_code_prefix
)
select * from cleaned
