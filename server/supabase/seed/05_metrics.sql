-- ============================================================================
-- 05_metrics.sql — regenerate the analytics_daily_metrics rollup from the
-- current assistance_requests + accessibility_issue_reports rows (seeded and
-- real). REPLACES all rows in analytics_daily_metrics (derived cache).
-- Run this last, and re-run after any future data change.
-- ============================================================================

delete from public.analytics_daily_metrics;

insert into public.analytics_daily_metrics
  (metric_date, venue_name, location_zone, total_requests, resolved_requests,
   total_barriers_reported, avg_response_time_sec, avg_resolution_time_sec,
   avg_user_satisfaction)
with req as (
  select date_trunc('day', created_at)::date          as metric_date,
         venue_name                                   as venue_name,
         location_zone                                as location_zone,
         count(*)                                     as total_requests,
         count(*) filter (where status in ('resolved', 'closed')) as resolved_requests,
         avg(response_time_seconds)  filter (where response_time_seconds is not null) as avg_response_time_sec,
         avg(resolution_time_seconds) filter (where resolution_time_seconds is not null) as avg_resolution_time_sec,
         avg(user_rating)            filter (where user_rating is not null)       as avg_user_satisfaction
  from public.assistance_requests
  group by 1, 2, 3
),
iss as (
  select date_trunc('day', created_at)::date as metric_date,
         venue_name                           as venue_name,
         location_zone                        as location_zone,
         count(*)                             as total_barriers_reported
  from public.accessibility_issue_reports
  group by 1, 2, 3
)
select
  coalesce(req.metric_date, iss.metric_date),
  coalesce(req.venue_name, iss.venue_name),
  coalesce(req.location_zone, iss.location_zone),
  coalesce(req.total_requests, 0),
  coalesce(req.resolved_requests, 0),
  coalesce(iss.total_barriers_reported, 0),
  round(req.avg_response_time_sec)::int,
  round(req.avg_resolution_time_sec)::int,
  round(req.avg_user_satisfaction, 2)
from req
full outer join iss
  on req.metric_date = iss.metric_date
 and req.venue_name = iss.venue_name
 and req.location_zone = iss.location_zone;
