-- Standalone purchase experience signal.
-- Scope: single-item orders only — ensures a 1-to-1 mapping between
-- a review and the product purchased. Reviews may reflect the delivery
-- experience, the product itself, or both; we do not attempt to separate
-- them. The satisfaction_scope column makes this explicit for consumers.

with single_item_orders as (
    select order_id
    from {{ ref('stg_order_items') }}
    group by order_id
    having count(*) = 1
),

-- get the one product per qualifying order
single_item_products as (
    select oi.order_id, oi.product_id
    from {{ ref('stg_order_items') }} oi
    inner join single_item_orders sio on oi.order_id = sio.order_id
),

experience_base as (
    select
        sip.product_id,
        r.review_score,
        r.review_creation_date,
        r.review_comment_message,
        r.review_comment_title
    from single_item_products sip
    inner join {{ ref('stg_order_reviews') }} r on sip.order_id = r.order_id
),

product_stats as (
    select
        product_id,
        count(*)                                                        as total_reviews,
        round(avg(review_score), 2)                                    as avg_satisfaction_score,
        count(case when review_score >= 4   then 1 end)                as positive_reviews,
        count(case when review_score = 3    then 1 end)                as neutral_reviews,
        count(case when review_score <= 2   then 1 end)                as negative_reviews,
        min(review_creation_date)                                      as first_review_date,
        max(review_creation_date)                                      as last_review_date,
        count(case
            when (review_comment_message is not null
                  and trim(review_comment_message) != '')
              or (review_comment_title is not null
                  and trim(review_comment_title) != '')
            then 1 end)                                                as reviews_with_text
    from experience_base
    group by product_id
),

-- split review period in half to detect improving or declining trend
trend_base as (
    select
        product_id,
        review_score,
        review_creation_date,
        min(review_creation_date) over (partition by product_id)       as first_date,
        max(review_creation_date) over (partition by product_id)       as last_date
    from experience_base
),

trend_stats as (
    select
        product_id,
        avg(case
            when review_creation_date <= dateadd(
                'second',
                datediff('second', first_date, last_date) / 2,
                first_date)
            then review_score end)                                      as first_half_avg,
        avg(case
            when review_creation_date > dateadd(
                'second',
                datediff('second', first_date, last_date) / 2,
                first_date)
            then review_score end)                                      as second_half_avg
    from trend_base
    group by product_id
)

select
    ps.product_id,
    dp.product_category,
    dp.price_tier,
    ps.total_reviews,
    ps.avg_satisfaction_score,
    round(ps.positive_reviews / ps.total_reviews::float * 100, 1)      as pct_positive,
    round(ps.neutral_reviews  / ps.total_reviews::float * 100, 1)      as pct_neutral,
    round(ps.negative_reviews / ps.total_reviews::float * 100, 1)      as pct_negative,
    case
        when ps.total_reviews >= 30 then 'High'
        when ps.total_reviews >= 10 then 'Medium'
        else 'Low'
    end                                                                 as satisfaction_confidence,
    case
        when ts.second_half_avg > ts.first_half_avg + 0.2              then 'Improving'
        when ts.second_half_avg < ts.first_half_avg - 0.2              then 'Declining'
        else 'Stable'
    end                                                                 as satisfaction_trend,
    ps.first_review_date,
    ps.last_review_date,
    (ps.reviews_with_text > 0)                                         as has_text_feedback,
    ps.reviews_with_text,
    'single_item_orders_only'                                          as satisfaction_scope

from product_stats ps
left join {{ ref('dim_products') }} dp on ps.product_id = dp.product_id
left join trend_stats               ts on ps.product_id = ts.product_id
