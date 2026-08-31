-- ============================================================================
-- 04_communication.sql — mock two-way dialogue sessions + messages (~6 months)
-- for communication-usage analytics (Module 3 data feeding Module 7):
-- session volume, input-modality mix, EN->MS vs EN->ZH ratio, session duration.
-- Idempotent via the 'SEED-' session_code prefix.
-- ============================================================================

select setseed(0.45);

delete from public.communication_dialogue_messages
where session_id in (select id from public.communication_dialogue_sessions where session_code like 'SEED-%');
delete from public.communication_dialogue_sessions where session_code like 'SEED-%';

-- ~160 dialogue sessions
insert into public.communication_dialogue_sessions
  (session_code, traveler_id, traveler_name, staff_name, traveler_sign_language,
   source_language, target_language, status, created_at, ended_at)
select
  'SEED-COMM-' || lpad(b.g::text, 4, '0'),
  b.tid,
  b.tname,
  b.sname,
  'BIM',
  'en',
  b.tgt,
  b.st,
  b.created_at,
  case when b.st = 'completed' then b.created_at + make_interval(secs => b.dur_secs) end
from (
  select
    t.g, t.created_at, t.d,
    case when t.d <= 2 and random() < 0.15 then 'active' else 'completed' end as st,
    (180 + random() * 900)::int as dur_secs,
    (array['ms','ms','ms','ms','ms','ms','zh','zh','zh','zh'])[1 + floor(random() * 10)] as tgt,
    case when random() < 0.4 then p.pid end as tid,
    (array['Aisyah Rahman','Wei Jie Tan','Arjun Patel','Daniel Wong','Farah Zainal',
           'Hui Ling Chan','Kavitha Raman','Liam Carter','Mei Ling Ong','Nabil Haikal'])[1 + floor(random() * 10)] as tname,
    (array['Counter Staff Lim','Info Desk Aina','Gate Officer Raj','Lounge Staff Farah'])[1 + floor(random() * 4)] as sname
  from (
    select g,
           (now() - make_interval(days => d))
             + make_interval(hours => h, mins => m, secs => s) as created_at,
           d
    from (
      select g,
             1 + floor(random() * 180)::int as d,
             (array[22,23,0,0,1,1,2,2,3,3,4,5,6,7,8,8,9,9,10,10,11,11,12,12,13,14,15])[1 + floor(random() * 27)] as h,
             floor(random() * 60)::int as m,
             floor(random() * 60)::int as s
      from generate_series(1, 160) g
    ) t
  ) t2
  left join lateral (
    select p.id as pid
    from public.user_profiles p
    join auth.users u on u.id = p.id
    where u.email like '%@seed.travelease.dev'
    order by random()
    limit 1
  ) p on true
) b;

-- dialogue messages (4-12 per session, traveler/staff alternating)
insert into public.communication_dialogue_messages
  (session_id, sender_role, sender_name, original_text, translated_text,
   source_language, target_language, input_modality, ai_confidence_score,
   is_corrected, created_at)
select
  s.id,
  case when m.i % 2 = 1 then 'traveler' else 'staff' end,
  case when m.i % 2 = 1 then s.traveler_name else s.staff_name end,
  case when m.i % 2 = 1
       then (array['Where is the nearest accessible toilet?','I need help with my boarding pass.',
                    'My flight is delayed, what should I do?','Can you please type that more slowly?',
                    'Where can I find a wheelchair?','I am deaf, please write here.',
                    'Which gate is boarding now?','Thank you for your help.'])[1 + x.jt]
       else (array['Your gate is B12, boarding starts at 3 pm.','I will call an interpreter for you.',
                    'The accessible toilet is 50 meters on the right.','Let me guide you to the counter.',
                    'Your luggage is on belt 4.','You are welcome.'])[1 + x.js]
  end,
  case when s.target_language = 'ms' then
       case when m.i % 2 = 1
            then (array['Di mana tandas mesra oku yang terdekat?','Saya perlukan bantuan untuk kad penumpang saya.',
                         'Penerbangan saya ditangguhkan, apa yang perlu saya buat?','Boleh anda taip dengan lebih perlahan?',
                         'Di mana saya boleh dapatkan kerusi roda?','Saya tidak boleh dengar, sila tulis di sini.',
                         'Pintu mana sedang boarding sekarang?','Terima kasih atas bantuan anda.'])[1 + x.jt]
            else (array['Pintu anda ialah B12, bermula jam 3 petang.','Saya akan panggil penterjemah isyarat untuk anda.',
                         'Tandas mesra oku terletak 50 meter di sebelah kanan.','Biar saya tunjukkan jalan ke kaunter.',
                         'Bagasi anda ada di belt 4.','Sama-sama.'])[1 + x.js]
       end
       else
       case when m.i % 2 = 1
            then (array['最近的无障碍厕所在哪里？','我需要人帮忙处理登机牌。',
                         '我的航班延误了，我该怎么办？','请慢慢打字，谢谢。',
                         '哪里可以借轮椅？','我是听障人士，请写在这里。',
                         '现在是哪个登机口在登机？','谢谢你的帮忙。'])[1 + x.jt]
            else (array['您的登机口是 B12，下午 3 点开始登机。','我会为您安排手语翻译员。',
                         '无障碍厕所在右边 50 米处。','让我带您到柜台。',
                         '您的行李在 4 号传送带。','不客气。'])[1 + x.js]
       end
  end,
  'en',
  s.target_language,
  case when m.i % 2 = 1
       then (array['sign_to_text','sign_to_text','sign_to_text','speech_to_text','speech_to_text',
                   'speech_to_text','typed_text','typed_text','quick_phrase'])[1 + floor(random() * 9)]
       else case when random() < 0.5 then 'typed_text' else 'speech_to_text' end
  end,
  round((0.80 + random() * 0.19)::numeric, 3),
  random() < 0.08,
  s.created_at + make_interval(secs => 20 + m.i * (15 + floor(random() * 45))::int)
from public.communication_dialogue_sessions s
cross join lateral generate_series(1, 4 + floor(random() * 9)::int) m(i)
cross join lateral (select floor(random() * 8)::int as jt, floor(random() * 6)::int as js) x
where s.session_code like 'SEED-%';
