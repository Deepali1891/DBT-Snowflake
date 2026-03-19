-- Decision-ready campaign scoring table.
-- Joins lifecycle, engagement, and experience signals into a composite
-- campaign_potential_score (0-100) and a campaign_recommendation label.
--
-- Score weights:
--   Lifecycle   30 pts  (what stage is the product in?)
--   Revenue trend 25 pts  (is momentum growing or declining?)
--   Engagement  25 pts  (do buyers come back?)
--   Experience  20 pts  (are buyers satisfied?)

with lifecycle as (
    select * from {{ ref('mart_product_lifecycle') }}
),

engagement as (
    select * from {{ ref('mart_product_engagement') }}
),

experience as (
    select * from {{ ref('mart_product_experience') }}
),

components as (
    select
        l.product_id,
        l.product_category,
        l.price_tier,
        l.lifecycle_classification,
        l.recent_trend,
        l.market_entry_date,
        l.active_selling_months,
        l.units_m1_m3 + l.units_m4_m6 + l.units_m7_m12 + l.units_m13_plus           as total_units_sold,
        l.revenue_m1_m3 + l.revenue_m4_m6 + l.revenue_m7_m12 + l.revenue_m13_plus    as total_revenue,
        coalesce(e.repeat_purchase_rate, 0)             as repeat_purchase_rate,
        coalesce(e.total_unique_buyers,  0)             as total_unique_buyers,
        e.seller_count,
        ex.avg_satisfaction_score,
        ex.satisfaction_confidence,
        ex.satisfaction_trend,
        coalesce(ex.total_reviews, 0)                   as total_reviews,
        ex.pct_positive,

        -- Lifecycle component (0–30)
        case l.lifecycle_classification
            when 'Long-term Classic' then 30
            when 'Steady Performer'  then 25
            when 'Shooting Star'     then 15
            when 'Emerging'          then 12
            when 'Niche'             then 10
            when 'Fading'            then 5
            else 10
        end                                             as lifecycle_component,

        -- Revenue trend component (0–25)
        case l.recent_trend
            when 'Growing'   then 25
            when 'Stable'    then 15
            when 'Declining' then 5
            else 10
        end                                             as trend_component,

        -- Engagement component (0–25) — driven by repeat purchase rate
        case
            when coalesce(e.repeat_purchase_rate, 0) >= 0.20 then 25
            when coalesce(e.repeat_purchase_rate, 0) >= 0.10 then 20
            when coalesce(e.repeat_purchase_rate, 0) >= 0.05 then 15
            when coalesce(e.repeat_purchase_rate, 0) >= 0.02 then 10
            else 5
        end                                             as engagement_component,

        -- Satisfaction component (0–20); defaults to 10 (neutral) when no data
        case
            when ex.avg_satisfaction_score is null      then 10
            when ex.avg_satisfaction_score >= 4.5       then 20
            when ex.avg_satisfaction_score >= 4.0       then 16
            when ex.avg_satisfaction_score >= 3.5       then 12
            when ex.avg_satisfaction_score >= 3.0       then 8
            else 4
        end                                             as satisfaction_component

    from lifecycle l
    left join engagement e  on l.product_id = e.product_id
    left join experience ex on l.product_id = ex.product_id
)

select
    product_id,
    product_category,
    price_tier,
    lifecycle_classification,
    recent_trend,
    market_entry_date,
    active_selling_months,
    total_units_sold,
    total_revenue,
    repeat_purchase_rate,
    total_unique_buyers,
    seller_count,
    avg_satisfaction_score,
    satisfaction_confidence,
    satisfaction_trend,
    total_reviews,
    pct_positive,
    lifecycle_component,
    trend_component,
    engagement_component,
    satisfaction_component,

    lifecycle_component + trend_component +
    engagement_component + satisfaction_component                       as campaign_potential_score,

    case
        when lifecycle_classification in ('Steady Performer', 'Long-term Classic')
             and lifecycle_component + trend_component +
                 engagement_component + satisfaction_component >= 65
            then 'High Priority'
        when lifecycle_classification in ('Fading', 'Shooting Star')
             and coalesce(avg_satisfaction_score, 0) >= 3.5
            then 'Reactivate'
        when lifecycle_component + trend_component +
             engagement_component + satisfaction_component >= 40
            then 'Monitor'
        else 'Retire'
    end                                                                 as campaign_recommendation

from components
