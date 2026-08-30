-- ============================================================================
-- 02_assistance.sql — mock assistance requests (+chat) and accessibility
-- issue reports over ~180 days, with realistic operational patterns.
-- Idempotent: rows are tagged SEED- and removed before re-seeding.
-- Real (app-created) rows are never touched.
-- ============================================================================

select setseed(0.43);

delete from public.assistance_chat_messages
where request_id in (select id from public.assistance_requests where request_code like 'SEED-%');
delete from public.assistance_requests where request_code like 'SEED-%';
delete from public.accessibility_issue_reports where report_code like 'SEED-%';

-- ---------------------------------------------------------------------------
-- Assistance requests (~520)
--   * hour-of-day weights put peaks at 7-11am and 5-9pm Malaysia time (UTC+8)
--   * ~10% breach the 5-minute response SLA, ~15% the 60-minute resolution SLA
--   * analytics_consent true for ~90% (FR-M7-07: dashboards count consented rows)
-- ---------------------------------------------------------------------------
insert into public.assistance_requests
  (request_code, traveler_name, preferred_communication, category, venue_name,
   location_zone, description, urgency, status, assigned_staff_id, assigned_staff_name,
   share_location, acknowledged_at, response_time_seconds, resolved_at,
   resolution_time_seconds, resolution_outcome, user_rating, user_feedback_comment,
   is_escalated, escalated_at, analytics_consent, created_at, updated_at)
select
  'SEED-' || lpad(b.g::text, 5, '0'),
  b.tname,
  b.comm,
  b.cat,
  i.name,
  b.zone,
  d.descr,
  b.urg,
  b.st,
  sf.id,
  sf.name,
  true,
  case when b.resp is not null then b.created_at + make_interval(secs => b.resp) end,
  b.resp,
  case when b.st in ('resolved', 'closed') and b.resp is not null and b.resol is not null
       then b.created_at + make_interval(secs => b.resp + b.resol) end,
  b.resol,
  b.outcome,
  b.rating,
  case when b.rating is not null and random() < 0.30
       then (array['Staff was very helpful and patient.','Problem solved quickly, thank you.',
                   'Had to wait quite a while but it was resolved.','Interpreter service was excellent.',
                   'Good follow-up from the staff member.'])[1 + floor(random() * 5)]
  end,
  b.esc,
  case when b.esc and b.resp is not null then b.created_at + make_interval(secs => b.resp) end,
  b.consent,
  b.created_at,
  b.created_at + make_interval(secs => coalesce(b.resp, 0) + coalesce(b.resol, 0))
from (
  select
    r.g, r.created_at, r.st, r.zone, r.cat, r.urg, r.comm, r.consent, r.tname,
    case when r.st in ('in_progress', 'resolved', 'closed')
              or (r.st = 'cancelled' and random() < 0.4)
         then (45 + power(random(), 2) * 255)::int
              + case when random() < 0.12 then (300 + random() * 900)::int else 0 end
    end as resp,
    case when r.st in ('resolved', 'closed')
         then (300 + power(random(), 2.2) * 2700)::int
              + case when random() < 0.15 then (1800 + random() * 3600)::int else 0 end
    end as resol,
    case when r.st = 'closed'
         then (array[5,5,5,5,5,5,5,5,5,4,4,4,4,4,4,4,3,3,3,2,2,1])[1 + floor(random() * 22)]
    end as rating,
    case when r.st = 'closed'
         then case when random() < 0.88 then 'fully_resolved' else 'partially_resolved' end
    end as outcome,
    case when r.st in ('resolved', 'closed') and random() < 0.05 then true else false end as esc
  from (
    select g,
           (now() - make_interval(days => d))
             + make_interval(hours => h, mins => m, secs => s) as created_at,
           case when d <= 2
                then (array['pending','pending','in_progress','in_progress','in_progress'])[1 + floor(random() * 5)]
                else (array['closed','closed','closed','closed','closed','closed','closed','closed',
                            'closed','closed','resolved','resolved','resolved','resolved','resolved',
                            'in_progress','in_progress','in_progress','cancelled','pending'])[1 + floor(random() * 20)]
           end as st,
           (array['Gate A1 - A10 Area','Gate A1 - A10 Area','Gate A1 - A10 Area','Gate A1 - A10 Area',
                  'Baggage Claim Hall','Baggage Claim Hall','Baggage Claim Hall',
                  'Check-in Counters 1-16','Check-in Counters 1-16',
                  'Immigration & Security','Gate B1 - B12 Area','Boarding Lounge C1 - C8'])[1 + floor(random() * 12)] as zone,
           (array['communication','communication','communication','communication',
                  'location','location','location',
                  'checkin','checkin','checkin',
                  'luggage','luggage',
                  'accessibility','accessibility',
                  'emergency','general','general'])[1 + floor(random() * 17)] as cat,
           (array['low','low','low','medium','medium','medium','medium','medium','high','high'])[1 + floor(random() * 10)] as urg,
           case when random() < 0.75 then 'chat' else 'location' end as comm,
           case when random() < 0.9 then true else false end as consent,
           (array['Aisyah Rahman','Wei Jie Tan','Arjun Patel','Daniel Wong','Farah Zainal',
                  'Hui Ling Chan','Kavitha Raman','Liam Carter','Mei Ling Ong','Nabil Haikal',
                  'Olivia Reyes','Rajesh Kumar','Sofia Marinescu','Tunku Aiman','Xin Yi Lim',
                  'Yusof Ismail','Chen Wei Goh','Emily Drake','Hakim Sulaiman','Grace Lau'])[1 + floor(random() * 20)] as tname
    from (
      select g,
             1 + floor(random() * 180)::int as d,
             (array[23,0,0,1,1,1,2,2,2,3,4,6,8,9,10,10,11,11,12,13,14,15,16,17])[1 + floor(random() * 24)] as h,
             floor(random() * 60)::int as m,
             floor(random() * 60)::int as s
      from generate_series(1, 520) g
    ) t
  ) r
) b
cross join (select name from public.institutions where name like 'Kuala Lumpur%' limit 1) i
cross join lateral (
  select s.id, s.name
  from public.institution_staff s
  order by random()
  limit 1
) sf,
lateral (
  select case b.cat
           when 'communication' then (array['Need help contacting my airline counter.',
                                            'Cannot hear the announcements at the gate.',
                                            'Need someone to explain the boarding procedure.'])[1 + floor(random() * 3)]
           when 'location' then (array['I am lost and cannot find my boarding gate.',
                                        'Cannot locate the accessible washroom.',
                                        'Need directions to the transfer desk.'])[1 + floor(random() * 3)]
           when 'checkin' then (array['Need assistance with the self check-in kiosk.',
                                       'Require help with baggage drop.',
                                       'Need priority boarding assistance.'])[1 + floor(random() * 3)]
           when 'luggage' then (array['My suitcase did not arrive at the belt.',
                                       'The luggage trolley is too heavy to manage.',
                                       'Damaged baggage after the flight.'])[1 + floor(random() * 3)]
           when 'accessibility' then (array['A wheelchair is needed from check-in to the gate.',
                                             'The ramp at the walkway is blocked.',
                                             'Need a sign language interpreter at the counter.'])[1 + floor(random() * 3)]
           when 'emergency' then (array['I feel unwell and need medical attention.',
                                         'The fire alarm rang but no visual alert was shown.',
                                         'I lost my companion in the crowd.'])[1 + floor(random() * 3)]
           else (array['Need general information about the airport facilities.',
                        'Would like help with the airport wifi.',
                        'Where can I find a charging point?'])[1 + floor(random() * 3)]
         end as descr
) d;

-- ---------------------------------------------------------------------------
-- Chat messages for the seeded requests
-- ---------------------------------------------------------------------------
insert into public.assistance_chat_messages
  (request_id, sender_type, sender_name, content, message_type, is_read, created_at)
select r.id,
       case when m.i % 2 = 1 then 'traveler' else 'staff' end,
       case when m.i % 2 = 1 then r.traveler_name else coalesce(r.assigned_staff_name, 'Staff') end,
       case when m.i % 2 = 1
            then (array['Hi, I submitted a request and need some assistance here.',
                         'I am still waiting at the location.',
                         'Could you update me on the status please?',
                         'Thank you for coming.'])[1 + floor(random() * 4)]
            else (array['Hello! We have received your request and staff is on the way.',
                         'Please hold on a moment, we are arranging assistance for you.',
                         'Is everything resolved for you now?',
                         'You are welcome. Safe travels!'])[1 + floor(random() * 4)]
       end,
       'text',
       true,
       least(
         r.created_at + make_interval(secs => 30 + m.i * (60 + floor(random() * 240))::int),
         coalesce(r.resolved_at, r.created_at + interval '90 minutes')
       )
from public.assistance_requests r
cross join lateral generate_series(1, 2 + floor(random() * 5)::int) m(i)
where r.request_code like 'SEED-%'
  and r.status in ('in_progress', 'resolved', 'closed')
  and random() < 0.85;

-- ---------------------------------------------------------------------------
-- Accessibility issue reports (~210)
-- ---------------------------------------------------------------------------
insert into public.accessibility_issue_reports
  (report_code, traveler_name, issue_type, venue_name, location_zone, description,
   severity, status, admin_notes, analytics_consent, created_at, updated_at)
select
  'SEED-R-' || lpad(b.g::text, 5, '0'),
  null, -- stays 'Anonymous' (anonymization-friendly)
  b.itype,
  i.name,
  b.zone,
  b.descr,
  b.sev,
  b.st,
  b.consent,
  case when b.st = 'resolved' and random() < 0.55
       then (array['Checked on site, signage has been added.','Temporary fix applied; permanent fix scheduled.',
                   'Announcement screen repaired and tested.','Staff briefed to announce stops verbally.',
                   'Ramp cleared; housekeeping notified.'])[1 + floor(random() * 5)]
  end,
  b.created_at,
  case when b.st = 'resolved'
       then b.created_at + make_interval(hours => 24 + floor(random() * 120)::int)
       else b.created_at end
from (
  select
    r.g, r.created_at, r.itype, r.sev, r.st, r.zone, r.consent,
    case r.itype
      when 'visual' then (array['No visual announcement was displayed for the flight delay.',
                                 'The caption screen at the gate is switched off.',
                                 'Important announcement was audio only.'])[1 + floor(random() * 3)]
      when 'queue' then (array['Queue calls are made by voice only, no visual display.',
                                'Missed my queue number because it was announced aloud.'])[1 + floor(random() * 2)]
      when 'sign' then (array['No sign language interpreter available at this counter.',
                               'Staff could not communicate in sign language.'])[1 + floor(random() * 2)]
      when 'alert' then (array['Emergency alarm had no flashing light alert.',
                                'No visual alert when boarding started.'])[1 + floor(random() * 2)]
      when 'access' then (array['The wheelchair ramp is blocked by trolleys.',
                                 'Lift to the mezzanine floor is out of order.',
                                 'Accessible toilet door is too heavy to open.'])[1 + floor(random() * 3)]
      else (array['Information counter is too high for wheelchair users.',
                   'Difficulty finding accessible route signage.'])[1 + floor(random() * 2)]
    end as descr
  from (
    select g,
           (now() - make_interval(days => d))
             + make_interval(hours => h, mins => m, secs => s) as created_at,
           (array['visual','visual','visual','visual','visual','visual','visual','visual',
                  'queue','queue','queue','queue',
                  'sign','sign','sign','alert','alert','alert',
                  'access','access','access','access','other','other'])[1 + floor(random() * 24)] as itype,
           (array['low','low','low','moderate','moderate','moderate','moderate','moderate','severe','severe'])[1 + floor(random() * 10)] as sev,
           case when (d < 10 and random() < 0.5) or random() >= 0.72
                then 'reported' else 'resolved' end as st,
           case when random() < 0.9 then true else false end as consent,
           (array['Gate A1 - A10 Area','Gate A1 - A10 Area','Gate A1 - A10 Area','Gate A1 - A10 Area','Gate A1 - A10 Area',
                  'Baggage Claim Hall','Baggage Claim Hall','Baggage Claim Hall',
                  'Check-in Counters 1-16','Check-in Counters 1-16','Check-in Counters 1-16',
                  'Immigration & Security','Gate B1 - B12 Area','Boarding Lounge C1 - C8'])[1 + floor(random() * 14)] as zone
    from (
      select g,
             1 + floor(random() * 180)::int as d,
             (array[23,0,0,1,1,1,2,2,2,3,4,6,8,9,10,10,11,11,12,13,14,15,16,17])[1 + floor(random() * 24)] as h,
             floor(random() * 60)::int as m,
             floor(random() * 60)::int as s
      from generate_series(1, 210) g
    ) t
  ) r
) b
cross join (select name from public.institutions where name like 'Kuala Lumpur%' limit 1) i;
