-- MELBOURNE CITY COUNCIL - SERVICE REQUESTS & SLA PERFORMANCE ANALYSIS
-- Database: melbourne_council.db 

-- Query 1: Executive KPI Summary
-- Purpose: Calculate overall council-wide service volume and core sla metrics
-- Key insight: 46,479 total requests with overall SLA breach rate of 38.59% 
-- and average completion time of 13.41 days. 
select
count(*) as total_requests,
count(case when sla_status = 'Pending' then 1 end) as pending_requests,
count(case when sla_status != 'Pending' then 1 end) as completed_requests,
count(case when sla_status = 'Breached' then 1 end) as breached_requests,
round((sum(is_sla_breached) * 100.0) / count(case when sla_status != 'Pending' then 1 end), 2) as sla_breach_rate_pct,
round(avg(case when sla_status != 'Pending' then days_to_complete end), 2) as avg_resolution_days
from fact_service_requests;

-- Query 2: Category Performance
-- Purpose: Evaluate request volume, breach rate, and resolution speed across service categories.
-- Key insight: 'Waste' drives the highest volume (20k+), but 'Graffiti' suffers the
-- worst breach rate (63.74%), acting as the primary operational issues.
select 
c.category as category,
count(*) as total_requests,
count(case when sla_status = 'Breached' then 1 end) as breached_requests,
round((sum(is_sla_breached) * 100.0) / count(case when sla_status != 'Pending' then 1 end), 2) as breached_rate_pct,
round(avg(case when sla_status != 'Pending' then days_to_complete end), 2) as avg_days_to_complete
from fact_service_requests f
left join dim_category c
on f.category_id = c.category_id
group by c.category
order by breached_rate_pct desc;

-- Query 3: Suburb Performance
-- Purpose: Identify top 5 suburbs with the worst SLA compliance (filtered for volume >= 500)
-- Key insight: Carlton and West Melbourne lead in breach rate (>41%), requiring localized depot resource adjustments. 
select
s.suburb_name as suburb,
count(*) as total_requests,
count(case when sla_status = 'Breached' then 1 end) as breached_requests,
round((sum(is_sla_breached) * 100.0) / count(case when sla_status != 'Pending' then 1 end), 2) as breached_rate_pct,
round(avg(case when sla_status != 'Pending' then days_to_complete end), 2) as avg_days_to_complete
from fact_service_requests f
left join dim_suburb s
on f.suburb_id = s.suburb_id
group by s.suburb_name
having count(*) >= 500
order by breached_rate_pct desc
limit 5;

-- Query 4: Workload Inflow by Day of Week
-- Purpose: Measure resident ticket intake volume and SLA performance across days of the week
-- Key insight: Monday experiences a massive demand spike (9,683 requests), causing ingestion
-- and dispatch delays that raise weekday breach rates (~38-40%)
select
d.day_of_week,
count(*) as total_requests,
count(case when sla_status = 'Breached' then 1 end) as breached_requests,
round((sum(is_sla_breached) * 100.0) / count(case when sla_status != 'Pending' then 1 end), 2) as breached_rate_pct
from fact_service_requests f
left join dim_date d
on f.received_date_key = d.date_key
group by d.day_of_week
order by total_requests desc;

-- Query 4a: Monthly Trend & Operational Stress Analysis
-- Purpose: Track month-over-month request volume growth, SLA breach rates, 
-- and identify data cut-off anomalies across the 24-month horizon.
-- Key insight: Inflow demand expanded by ~25% from 2015 (~1.7k/mo) to 2016 
-- (~2.2k/mo) while breach rates remained saturated around 37-43%. 
--  November 2016 reflects a mid-month data cut-off (partial month).
select
d.year,
d.month,
d.month_name,
count(*) as total_requests,
count(case when sla_status = 'Breached' then 1 end) as breached_requests,
round((sum(is_sla_breached) * 100.0) / count(case when sla_status != 'Pending' then 1 end), 2) as breached_rate_pct
from fact_service_requests f
left join dim_date d ON f.received_date_key = d.date_key
group by d.year, d.month, d.month_name
order by d.year, d.month;

-- Query 4b: Hypothesis Testing - Category Share Accross Days of the Week
-- Purpose: Verify if Monday's breach spike is driven by an influx of difficult service types. 
-- Key finding: Category distribution remains nearly identical everyday (~44% Waste, ~20% Graffiti), 
-- indicating that the breach spike is driven by volume rather than service type.
select
d.day_of_week,
c.category,
count(*) as total_requests,
round(count(*) * 100.0 / sum(count(*)) over (partition by d.day_of_week), 2) as category_share_pct
from fact_service_requests f
left join dim_date d
on f.received_date_key = d.date_key
left join dim_category c
on f.category_id = c.category_id
group by d.day_of_week, c.category
order by 
CASE d.day_of_week 
        WHEN 'Monday' THEN 1 WHEN 'Tuesday' THEN 2 WHEN 'Wednesday' THEN 3 
        WHEN 'Thursday' THEN 4 WHEN 'Friday' THEN 5 WHEN 'Saturday' THEN 6 WHEN 'Sunday' THEN 7 
END,
category_share_pct DESC;

-- Query 4c: Hypothesis Testing - Data Quality Impact (Unspecified Suburb vs SLA & Backlog)
-- Purpose: Verify if missing geographic attribution correlates with higher SLA breach or pending rates. 
-- Key finding: Unspecified locations account for 67.6% of active backlog (573/848 tickets) with nearly 
-- double the pending rate (2.30% vs 1.27%) and extend average resolution time by +8.0 days (18.8 vs 10.8 days). 
-- However, completed breach rates remain unaffected (~38-39%), proving that missing suburb data 
-- primarily paralyzes intake triage and dispatch rather than on-site task completion.
select 
case 
        when s.suburb_name = 'Unspecified' or s.suburb_name is null then 'Unspecified'
        else 'Specified'
end as location_status,
count(*) as total_requests,
count(case when f.sla_status = 'Pending' then 1 end) as pending_count,
round(count(case when f.sla_status = 'Pending' then 1 end) * 100.0 / count(*), 2) as pending_rate_pct,
round(
count(case when f.sla_status = 'Breached' then 1 end) * 100.0 / nullif(count(case when f.sla_status != 'Pending' then 1 end), 0),
2
) as breach_rate_pct,
round(avg(f.days_to_complete), 1) as avg_days
from fact_service_requests f 
left join dim_suburb s on f.suburb_id = s.suburb_id
group by location_status;

-- Query 5: Operational Outliers
-- Purpose: Detect top 10 longest-running breached tickets with valid suburb attribution. 
-- Key insight: Severe delays concentrate in Parking Meter Service and Graffiti Removal, with resolution time exceeding 300-500 days against SLA targets.
select 
f.request_id,
s.suburb_name as suburb,
c.category,
c.service_desc,
f.sla_target_days,
f.days_to_complete,
(f.days_to_complete - f.sla_target_days) as days_overdue
from fact_service_requests f
left join dim_suburb s
on f.suburb_id = s.suburb_id
left join dim_category c
on f.category_id = c.category_id
where sla_status = 'Breached'
and s.suburb_name != 'Unspecified'
order by days_to_complete desc
limit 10;

-- Query 6: Active Backlog & Audit (Pending Requests Breakdown)
-- Purpose: Audit the 848 unclosed tickets across operational statuses and calculate ageing days.
-- Key insight: Unresolved requests are spread across NEW, WIP, and ACTIONED statuses,
-- with some tickets lingering for hundreds of days without final closure.
select 
f.request_status,
count(*) as pending_count,
round(count(*) * 100.0 / (select count(*) from fact_service_requests where sla_status = 'Pending'), 2) as share_pct,
    min(f.days_to_complete) as min_ageing_days,
    round(avg(f.days_to_complete), 1) as avg_ageing_days,
    max(f.days_to_complete) as max_ageing_days
from fact_service_requests f
where f.sla_status = 'Pending'
group by f.request_status
order by pending_count desc;

-- Query 7: Granular Sub-Service Performance Gap & SLA Breach Ranking
-- Purpose: Drill down from high-level categories into 27 granular 
--   service descriptions (service_desc) to identify specific operational bottlenecks.
-- Filter: Minimum 50 requests threshold to ensure statistical relevance.
-- Key insight: 
--   - Highlights unrealistic SLAs ('Parking Meter Service' target of 3.0 days 
--     vs actual 92.5 days, creating a massive 89.5-day gap and 71.17% breach rate).
--   - Pinpoints high-volume risk areas like 'Graffiti Removal' (9,174 tickets, 63.74% breach).
select 
c.category,
c.service_desc,
count(f.request_id) as total_requests,
round(avg(f.sla_target_days), 1) as sla_target,
round(avg(case when f.sla_status != 'Pending' then f.days_to_complete end), 1) as actual_avg_days,
round(avg(case when f.sla_status != 'Pending' then f.days_to_complete end) - avg(f.sla_target_days), 1) as target_gap_days,
round(100.0 * sum(f.is_sla_breached) / count(case when f.sla_status != 'Pending' then 1 end), 2) as breach_rate_pct
from fact_service_requests f
join dim_category c on f.category_id = c.category_id
group by c.category, c.service_desc
having total_requests >= 50
order by breach_rate_pct desc;

-- Query 8: Suburb x Service Cross-Analysis (Geographic Bottlenecks)
-- Purpose:
--   Examine specific sub-services (service_desc) across individual suburbs 
--   (excluding 'Unspecified') to locate localized operational failure points.
-- Filters & Threshold:
--   - Excludes suburb_name = 'Unspecified'.
--   - Minimum 100 requests per suburb-service cluster for statistical relevance.
-- Core Insights:
--   - 'Park Cleaning' suffers the worst failure rate in inner suburbs:
--     North Melbourne (84.91%), Carlton (84.78%), and Melbourne CBD (77.36%), 
--     averaging 41-44 resolution days.
--   - 'Graffiti Removal' shows systemic delays across nearly all suburbs:
--     Surpasses 70% breach rate in West Melbourne, Kensington, North Melbourne, 
--     and Parkville, with high volume in Carlton (995 tickets, 66.36% breach rate).
select
s.suburb_name,
c.service_desc,
count(f.request_id) as total_requests,
sum(f.is_sla_breached) as breached_count,
round(100.0 * sum(f.is_sla_breached) / count(case when f.sla_status != 'Pending' then 1 end), 2) as breach_rate_pct,
round(avg(case when f.sla_status != 'Pending' then f.days_to_complete end), 1) as actual_avg_days
from fact_service_requests f
join dim_suburb s on f.suburb_id = s.suburb_id
join dim_category c on f.category_id = c.category_id
where s.suburb_name != 'Unspecified'
group by s.suburb_name, c.service_desc
having total_requests >= 100
order by breach_rate_pct desc;

-- Query 9: SLA Breach Delay Severity Distribution by Service Description
-- Purpose:
--   Categorize breached tickets into delay tiers (Minor: 1-7d, Moderate: 8-30d, 
--   Severe: >30d) across granular sub-services to distinguish between operational 
--   backlog vs systemic process failure.
-- Insights:
--   - 'Park Cleaning' (639 tickets) and 'Parking Meter Service' (426 tickets) 
--     suffer severe systemic failure (>30 days delay), confirming procurement/contractor bottlenecks.
--   - 'Graffiti Removal' delays stem from volume overload rather than abandonment, 
--     with 5,310 tickets falling into minor and moderate delay buckets (1-30 days).
--   - 'Traffic Management' shows significant heavy delays (312 tickets >30 days).
select 
c.category,
c.service_desc,
count(case when f.days_to_complete - f.sla_target_days >= 1 and f.days_to_complete - f.sla_target_days <= 7 then 1 end) as minor_breach,
count(case when f.days_to_complete - f.sla_target_days >=8 and f.days_to_complete - f.sla_target_days <= 30 then 1 end) as moderate_breach,
count(case when f.days_to_complete - f.sla_target_days > 30 then 1 end) as severe_breach
from fact_service_requests f
join dim_category c on f.category_id = c.category_id
where f.sla_status = 'Breached'
group by c.category, c.service_desc
order by severe_breach desc;