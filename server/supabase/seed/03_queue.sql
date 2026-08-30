-- ============================================================================
-- 03_queue.sql — historical queue numbers + events (~6 months) for wait-time,
-- abandonment and peak-hour analytics (Module 2 data feeding Module 7).
-- Only terminal statuses (completed/cancelled) are seeded so live queue views
-- are never polluted. Idempotent via the 'SEED-' number prefix.
-- ============================================================================

select setseed(0.44);

delete from public.queue_events qe
using public.queue_numbers qn
where qe.queue_number_id = qn.id and qn.number like 'SEED-%';
delete from public.queue_numbers where number like 'SEED-%';

-- ~80 historical numbers per queue line
insert into public.queue_numbers
  (queue_line_id, institution_id, number, status, traveler_id,
   called_at, completed_at, created_at, updated_at)
select
  l.id,
  l.institution_id,
  'SEED-' || lpad(b.g::text, 4, '0'),
  b.st,
  case when random() < 0.30 then u.uid end,
  case when b.st = 'completed' then b.created_at + make_interval(secs => b.wait_secs) end,
  case when b.st = 'completed'
       then b.created_at + make_interval(secs => b.wait_secs + b.svc_secs) end,
  b.created_at,
  case when b.st = 'completed'
       then b.created_at + make_interval(secs => b.wait_secs + b.svc_secs)
       else b.created_at + make_interval(secs => 60 + floor(random() * 540)::int) end
from public.queue_lines l
cross join lateral (
  select
    t.g,
    t.created_at,
    case when random() < 0.92 then 'completed' else 'cancelled' end as st,
    (120 + power(random(), 2) * 780)::int
      + case when random() < 0.06 then (600 + random() * 1800)::int else 0 end as wait_secs,
    (180 + random() * 420)::int as svc_secs
  from (
    select g,
           (now() - make_interval(days => d))
             + make_interval(hours => h, mins => floor(random() * 60)::int, secs => floor(random() * 60)::int) as created_at
    from (
      select g,
             1 + floor(random() * 180)::int as d,
             (array[22,23,0,0,1,1,2,2,3,3,4,5,6,7,8,8,9,9,10,10,11,11,12,12,13,14,15])[1 + floor(random() * 27)] as h
      from generate_series(1, 80) g
    ) t
  ) t
) b
left join lateral (
  select id as uid from auth.users where email like '%@seed.travelease.dev' order by random() limit 1
) u on true
where l.status <> 'closed';

-- matching audit events
insert into public.queue_events
  (institution_id, queue_line_id, queue_number_id, event_type, event_number, details, created_at)
select qn.institution_id, qn.queue_line_id, qn.id, 'created', qn.number,
       '{"seeded": true}'::jsonb, qn.created_at
from public.queue_numbers qn
where qn.number like 'SEED-%';

insert into public.queue_events
  (institution_id, queue_line_id, queue_number_id, event_type, event_number, details, created_at)
select qn.institution_id, qn.queue_line_id, qn.id,
       case when qn.status = 'completed' then 'completed' else 'cancelled' end,
       qn.number,
       '{"seeded": true}'::jsonb,
       qn.updated_at
from public.queue_numbers qn
where qn.number like 'SEED-%';
