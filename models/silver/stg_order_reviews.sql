with source as (
    select
        "c1" as review_id,
        "c2" as order_id,
        "c3" as review_score,
        "c4" as review_comment_title,
        "c5" as review_comment_message,
        "c6" as review_creation_date,
        "c7" as review_answer_timestamp
    from {{ source('bronze', 'raw_order_reviews') }}
),
deduped as (
    select *,
        row_number() over (partition by review_id order by review_creation_date desc) as row_num
    from source
    where review_id is not null
      and order_id is not null
),
cleaned as (
    select
        review_id,
        order_id,
        cast(review_score as integer)                  as review_score,
        trim(review_comment_title)                     as review_comment_title,
        trim(review_comment_message)                   as review_comment_message,
        cast(review_creation_date as timestamp_ntz)    as review_creation_date,
        cast(review_answer_timestamp as timestamp_ntz) as review_answer_timestamp
    from deduped
    where row_num = 1
      and review_score between 1 and 5
)
select * from cleaned
