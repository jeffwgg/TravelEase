


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."apply_announcement_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.status = 'withdrawn' then
    return new;
  end if;
  if new.expires_at is not null and new.expires_at <= now() then
    new.status := 'expired';
  elsif new.published_at is not null and new.published_at > now() then
    new.status := 'scheduled';
  else
    new.status := 'active';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."apply_announcement_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_manage_announcement_institution"("p_institution_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select auth.uid() is not null and (
    exists (
      select 1
      from public.institutions i
      where i.id = p_institution_id
        and i.account_user_id = auth.uid()
    )
    or exists (
      select 1
      from public.institution_staff s
      where s.institution_id = p_institution_id
        and s.auth_user_id = auth.uid()
        and s.active
        and s.role = 'staff'
    )
  );
$$;


ALTER FUNCTION "public"."can_manage_announcement_institution"("p_institution_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_manage_sos_institution"("p_institution_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select auth.uid() is not null and (
    exists (select 1 from public.institutions i
      where i.id = p_institution_id and i.account_user_id = auth.uid())
    or exists (select 1 from public.institution_staff s
      where s.institution_id = p_institution_id
        and s.auth_user_id = auth.uid() and s.active = true)
  );
$$;


ALTER FUNCTION "public"."can_manage_sos_institution"("p_institution_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_staff_institution_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select staff.institution_id
  from public.institution_staff staff
  where staff.auth_user_id = (select auth.uid())
    and staff.role = 'staff'
    and staff.active = true
  limit 1;
$$;


ALTER FUNCTION "public"."current_staff_institution_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_service_area_announcements"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if exists (
    select 1 from public.venue_sessions s
    where s.service_area_id = old.id and s.ended_at is null
  ) then
    raise exception
      'This service area cannot be deleted while travellers have an active venue session. Ask them to end their session first.';
  end if;

  delete from public.announcements
  where service_area_id = old.id;

  return old;
end;
$$;


ALTER FUNCTION "public"."delete_service_area_announcements"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_service_area_dependents"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if exists (
    select 1 from public.venue_sessions s
    where s.service_area_id = old.id and s.ended_at is null
  ) then
    raise exception
      'This service area cannot be deleted while travellers have an active venue session. Ask them to end their session first.';
  end if;

  -- Queue events and explicit queue-number records depend on their line.
  -- Delete them before the line so this works whether or not older database
  -- installations defined cascading foreign keys.
  delete from public.queue_events
  where queue_line_id in (
    select id from public.queue_lines where service_area_id = old.id
  );

  delete from public.queue_numbers
  where queue_line_id in (
    select id from public.queue_lines where service_area_id = old.id
  );

  delete from public.queue_lines where service_area_id = old.id;

  delete from public.announcements where service_area_id = old.id;

  return old;
end;
$$;


ALTER FUNCTION "public"."delete_service_area_dependents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_queue_line_not_closed"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    line_status text;
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        SELECT status INTO line_status
        FROM public.queue_lines
        WHERE id = NEW.queue_line_id;

        IF line_status = 'closed' THEN
            RAISE EXCEPTION
                'Queue line % is closed: queue number statuses cannot be changed until it reopens.',
                NEW.queue_line_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."enforce_queue_line_not_closed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_service_area_assignment"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  selected_name text;
begin
  if new.service_area_id is null then
    return new;
  end if;

  select name into selected_name
  from public.service_areas
  where id = new.service_area_id
    and institution_id = new.institution_id
    and active = true;

  if selected_name is null then
    raise exception 'Service area must be active and belong to this institution'
      using errcode = '23503';
  end if;

  if tg_table_name = 'queue_lines' then
    new.service_area := selected_name;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_service_area_assignment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_sos_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if new.status = old.status then
    return new;
  end if;
  if old.status = 'sent' and new.status = 'acknowledged' then
    new.acknowledged_at = coalesce(old.acknowledged_at, now());
    return new;
  end if;
  if ((old.status = 'acknowledged' and new.status in ('assigned', 'resolved'))
        or (old.status = 'assigned' and new.status in ('en_route', 'resolved'))
        or (old.status = 'en_route' and new.status = 'resolved')) then
    new.acknowledged_at = coalesce(old.acknowledged_at, now());
    new.resolved_at = coalesce(old.resolved_at, now());
    return new;
  end if;
  raise exception 'Invalid SOS status transition from % to %', old.status, new.status;
end;
$$;


ALTER FUNCTION "public"."enforce_sos_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sos_traveller_names"("p_request_ids" "uuid"[]) RETURNS TABLE("request_id" "uuid", "full_name" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select r.id, nullif(btrim(p.full_name), '')
  from public.sos_requests r
  left join public.user_profiles p on p.id = r.traveller_id
  where r.id = any(p_request_ids)
    and auth.uid() is not null
    and (
      exists (select 1 from public.institutions i
        where i.id = r.institution_id and i.account_user_id = auth.uid())
      or exists (select 1 from public.institution_staff s
        where s.id = r.assigned_staff_id and s.institution_id = r.institution_id
          and s.auth_user_id = auth.uid() and s.active and s.role = 'staff')
    );
$$;


ALTER FUNCTION "public"."get_sos_traveller_names"("p_request_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_traveller_sos_history"() RETURNS SETOF "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  with owned_requests as (
    select r.*, i.name as institution_name, a.name as service_area_name,
      s.name as staff_name,
      case when r.status <> 'resolved' and s.active then s.contact_number end as staff_contact
    from public.sos_requests r
    left join public.institutions i on i.id = r.institution_id
    left join public.service_areas a on a.id = r.service_area_id
      and a.institution_id = r.institution_id
    left join public.institution_staff s on s.id = r.assigned_staff_id
      and s.institution_id = r.institution_id
    where r.traveller_id = auth.uid()
  ), owned_events as (
    select e.* from public.traveller_sos_events e where e.traveller_id = auth.uid()
  ), history as (
    select jsonb_build_object(
      'id', coalesce(r.id, e.id),
      'triggered_at', coalesce(r.triggered_at, e.triggered_at),
      'ended_at', e.ended_at, 'status', coalesce(e.status, 'unknown'),
      'latitude', coalesce(r.latitude, e.latitude),
      'longitude', coalesce(r.longitude, e.longitude),
      'institution_name', coalesce(r.institution_name, e.institution_name),
      'service_area_name', coalesce(r.service_area_name, e.service_area_name),
      'institution_status', case when r.id is not null then 'requestSent' else e.institution_status end,
      'institution_attempted_at', coalesce(r.triggered_at, e.institution_attempted_at),
      'contact_name', e.contact_name, 'contact_status', coalesce(e.contact_status, 'notRecorded'),
      'contact_attempted_at', e.contact_attempted_at,
      'request', case when r.id is null then null else jsonb_build_object(
        'id', r.id, 'status', r.status, 'acknowledged_at', r.acknowledged_at,
        'resolved_at', r.resolved_at, 'staff_name', r.staff_name, 'staff_contact', r.staff_contact
      ) end
    ) as entry, coalesce(r.triggered_at, e.triggered_at) as event_time
    from owned_requests r
    -- At most one metadata event per request. Prefer actual contact metadata
    -- over any legacy backfilled snapshot. A timestamp match covers a failed
    -- client-side link write after successful institution request creation.
    left join lateral (
      select e.* from owned_events e where e.sos_request_id = r.id
        or (e.sos_request_id is null and e.triggered_at = r.triggered_at)
      order by e.contact_attempted_at desc nulls last, e.id limit 1
    ) e on true
    union all
    select jsonb_build_object(
      'id', e.id, 'triggered_at', e.triggered_at, 'ended_at', e.ended_at,
      'status', e.status, 'latitude', e.latitude, 'longitude', e.longitude,
      'institution_name', e.institution_name, 'service_area_name', e.service_area_name,
      'institution_status', e.institution_status, 'institution_attempted_at', e.institution_attempted_at,
      'contact_name', e.contact_name, 'contact_status', e.contact_status,
      'contact_attempted_at', e.contact_attempted_at, 'request', null
    ), e.triggered_at from owned_events e
    where not exists (select 1 from owned_requests r where r.id = e.sos_request_id
      or (e.sos_request_id is null and r.triggered_at = e.triggered_at))
  ) select entry from history order by event_time desc, entry->>'id';
$$;


ALTER FUNCTION "public"."get_traveller_sos_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_analytics"() RETURNS TABLE("total_users" bigint, "signups" "jsonb")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    count(*),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('month', m, 'count', c) ORDER BY m)
      FROM (SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS m, count(*) AS c
            FROM public.user_profiles GROUP BY 1) s
    ), '[]'::jsonb)
  FROM public.user_profiles;
$$;


ALTER FUNCTION "public"."get_user_analytics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) RETURNS double precision
    LANGUAGE "sql" IMMUTABLE STRICT PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
  select 6371000.0 * 2.0 * asin(sqrt(least(1.0, greatest(0.0,
    power(sin(radians(latitude_b - latitude_a) / 2.0), 2) +
    cos(radians(latitude_a)) * cos(radians(latitude_b)) *
    power(sin(radians(longitude_b - longitude_a) / 2.0), 2)
  ))));
$$;


ALTER FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_institution_account"("p_institution_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.institutions institution
    WHERE institution.id = p_institution_id
      AND institution.account_user_id = auth.uid()
      AND institution.active
  )
  OR EXISTS (
    SELECT 1
    FROM public.institution_staff staff
    WHERE staff.institution_id = p_institution_id
      AND staff.auth_user_id = auth.uid()
      AND staff.active = true
  );
$$;


ALTER FUNCTION "public"."is_institution_account"("p_institution_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_traveller_account"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select auth.uid() is not null
    and exists (select 1 from public.user_profiles p where p.id = auth.uid())
    and not exists (select 1 from public.institutions i where i.account_user_id = auth.uid())
    and not exists (select 1 from public.institution_staff s where s.auth_user_id = auth.uid());
$$;


ALTER FUNCTION "public"."is_traveller_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_venue_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.institution_staff s
    where s.auth_user_id = auth.uid()
      and s.active = true
  )
  or exists (
    select 1 from public.institutions i
    where i.account_user_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."is_venue_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_institution_traveller_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if exists (
    select 1 from public.institutions
    where account_user_id = new.id
  ) or exists (
    select 1 from auth.users
    where id = new.id
      and raw_user_meta_data ->> 'account_type' = 'institution'
  ) then
    raise exception 'Institution accounts cannot create traveller profiles';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."prevent_institution_traveller_profile"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."queue_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "service_area" "text" NOT NULL,
    "prefix" "text" NOT NULL,
    "current_number" "text" NOT NULL,
    "upcoming_number" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "estimated_service_minutes" integer DEFAULT 5 NOT NULL,
    "operating_hours" "text",
    "staff_notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "max_tracking_number" integer,
    "service_area_id" "uuid",
    CONSTRAINT "queue_lines_current_number_check" CHECK ((("char_length"(TRIM(BOTH FROM "current_number")) >= 1) AND ("char_length"(TRIM(BOTH FROM "current_number")) <= 24))),
    CONSTRAINT "queue_lines_estimated_service_minutes_check" CHECK ((("estimated_service_minutes" >= 1) AND ("estimated_service_minutes" <= 240))),
    CONSTRAINT "queue_lines_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 1) AND ("char_length"(TRIM(BOTH FROM "name")) <= 100))),
    CONSTRAINT "queue_lines_prefix_check" CHECK ((("char_length"(TRIM(BOTH FROM "prefix")) >= 1) AND ("char_length"(TRIM(BOTH FROM "prefix")) <= 8))),
    CONSTRAINT "queue_lines_service_area_check" CHECK ((("char_length"(TRIM(BOTH FROM "service_area")) >= 1) AND ("char_length"(TRIM(BOTH FROM "service_area")) <= 160))),
    CONSTRAINT "queue_lines_staff_notes_check" CHECK ((("staff_notes" IS NULL) OR ("char_length"("staff_notes") <= 2000))),
    CONSTRAINT "queue_lines_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'paused'::"text", 'closed'::"text", 'reset'::"text"]))),
    CONSTRAINT "queue_lines_upcoming_number_check" CHECK ((("char_length"(TRIM(BOTH FROM "upcoming_number")) >= 1) AND ("char_length"(TRIM(BOTH FROM "upcoming_number")) <= 24)))
);


ALTER TABLE "public"."queue_lines" OWNER TO "postgres";


COMMENT ON COLUMN "public"."queue_lines"."max_tracking_number" IS 'How many queue numbers ahead of the current serving number are traceable by travellers. NULL means the application default of 100.';



COMMENT ON COLUMN "public"."queue_lines"."service_area_id" IS 'Authoritative service-area assignment; queue_lines.service_area is the synced display label.';



CREATE OR REPLACE FUNCTION "public"."queue_call_next"("p_queue_line_id" "uuid") RETURNS "public"."queue_lines"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  line_record public.queue_lines;
  next_number text;
  called_id uuid;
begin
  select * into line_record from public.queue_lines where id = p_queue_line_id for update;
  if line_record.id is null then raise exception 'Queue line not found.'; end if;
  if not public.is_institution_account(line_record.institution_id) then
    raise exception 'Active institution account access is required.';
  end if;
  if line_record.status <> 'active' then raise exception 'Only active queue lines can call the next number.'; end if;

  insert into public.queue_numbers (queue_line_id, institution_id, number, status, called_at)
  values (line_record.id, line_record.institution_id, line_record.upcoming_number, 'called', now())
  on conflict (queue_line_id, number) do update
    set status = 'called', called_at = now(), completed_at = null
  returning id into called_id;

  next_number := public.queue_increment_number(line_record.upcoming_number);
  insert into public.queue_numbers (queue_line_id, institution_id, number, status)
  values (line_record.id, line_record.institution_id, next_number, 'waiting')
  on conflict (queue_line_id, number) do nothing;

  update public.queue_lines
    set current_number = line_record.upcoming_number, upcoming_number = next_number
    where id = line_record.id
    returning * into line_record;

  insert into public.queue_events (institution_id, queue_line_id, queue_number_id, event_type, event_number, created_by)
  values (line_record.institution_id, line_record.id, called_id, 'called', line_record.current_number, auth.uid());
  return line_record;
end;
$$;


ALTER FUNCTION "public"."queue_call_next"("p_queue_line_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_increment_number"("p_number" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $_$
declare
  parts text[];
begin
  parts := regexp_match(trim(p_number), '^(.*?)([0-9]+)$');
  if parts is null then
    return trim(p_number) || '-001';
  end if;
  return parts[1] || lpad((parts[2]::integer + 1)::text, char_length(parts[2]), '0');
end;
$_$;


ALTER FUNCTION "public"."queue_increment_number"("p_number" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."queue_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "queue_line_id" "uuid" NOT NULL,
    "queue_number_id" "uuid",
    "event_type" "text" NOT NULL,
    "event_number" "text",
    "created_by" "uuid",
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "queue_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['created'::"text", 'updated'::"text", 'called'::"text", 'notified'::"text", 'cancelled'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."queue_events" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "public"."queue_events"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_line public.queue_lines%rowtype;
  v_event public.queue_events%rowtype;
begin
  select * into v_line from public.queue_lines where id = p_queue_line_id;
  if not found or not public.queue_staff_can_manage(v_line.institution_id) then
    raise exception 'You do not have permission to update this queue line.';
  end if;

  insert into public.queue_events (
    institution_id, queue_line_id, event_type, event_number, created_by, details
  ) values (
    v_line.institution_id, v_line.id, p_event_type, trim(p_number), auth.uid(),
    coalesce(p_details, '{}'::jsonb)
  ) returning * into v_event;
  return v_event;
end;
$$;


ALTER FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."queue_numbers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "queue_line_id" "uuid" NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "number" "text" NOT NULL,
    "status" "text" DEFAULT 'waiting'::"text" NOT NULL,
    "traveler_id" "uuid",
    "called_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "queue_numbers_number_check" CHECK ((("char_length"(TRIM(BOTH FROM "number")) >= 1) AND ("char_length"(TRIM(BOTH FROM "number")) <= 24))),
    CONSTRAINT "queue_numbers_status_check" CHECK (("status" = ANY (ARRAY['waiting'::"text", 'called'::"text", 'cancelled'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."queue_numbers" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_mark_number"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") RETURNS "public"."queue_numbers"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  line_record public.queue_lines;
  number_record public.queue_numbers;
begin
  if p_status not in ('completed', 'cancelled') then
    raise exception 'Queue number status must be completed or cancelled.';
  end if;
  select * into line_record from public.queue_lines where id = p_queue_line_id;
  if line_record.id is null then raise exception 'Queue line not found.'; end if;
  if line_record.status = 'closed' then
    raise exception 'This queue line is closed — its queue numbers cannot be updated.';
  end if;
  if not public.is_institution_account(line_record.institution_id) then
    raise exception 'Active institution account access is required.';
  end if;

  insert into public.queue_numbers (queue_line_id, institution_id, number, status, completed_at)
  values (line_record.id, line_record.institution_id, trim(p_number), p_status, now())
  on conflict (queue_line_id, number) do update
    set status = p_status, completed_at = now()
  returning * into number_record;

  insert into public.queue_events (institution_id, queue_line_id, queue_number_id, event_type, event_number, created_by)
  values (line_record.institution_id, line_record.id, number_record.id, p_status, number_record.number, auth.uid());
  return number_record;
end;
$$;


ALTER FUNCTION "public"."queue_mark_number"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_mark_number_and_call_next"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  line_record public.queue_lines;
  number_record public.queue_numbers;
  called_record public.queue_numbers;
  called_number text;
  next_number text;
begin
  if p_status not in ('completed', 'cancelled') then
    raise exception 'Queue number status must be completed or cancelled.';
  end if;
  if trim(coalesce(p_number, '')) = '' then raise exception 'Queue number is required.'; end if;

  select * into line_record from public.queue_lines where id = p_queue_line_id for update;
  if line_record.id is null then raise exception 'Queue line not found.'; end if;
  if line_record.status <> 'active' then raise exception 'Only active queue lines can advance.'; end if;
  if not public.is_institution_account(line_record.institution_id) then
    raise exception 'Active institution account access is required.';
  end if;

  insert into public.queue_numbers (queue_line_id, institution_id, number, status, completed_at)
  values (line_record.id, line_record.institution_id, trim(p_number), p_status, now())
  on conflict (queue_line_id, number) do update
    set status = p_status, completed_at = now()
  returning * into number_record;

  insert into public.queue_events (
    institution_id, queue_line_id, queue_number_id, event_type, event_number, created_by
  ) values (
    line_record.institution_id, line_record.id, number_record.id,
    p_status, number_record.number, auth.uid()
  );

  if number_record.number = line_record.upcoming_number then
    called_number := public.queue_increment_number(line_record.upcoming_number);
  else
    called_number := line_record.upcoming_number;
  end if;

  insert into public.queue_numbers (queue_line_id, institution_id, number, status, called_at)
  values (line_record.id, line_record.institution_id, called_number, 'called', now())
  on conflict (queue_line_id, number) do update
    set status = 'called', called_at = now(), completed_at = null
  returning * into called_record;

  next_number := public.queue_increment_number(called_number);
  insert into public.queue_numbers (queue_line_id, institution_id, number, status)
  values (line_record.id, line_record.institution_id, next_number, 'waiting')
  on conflict (queue_line_id, number) do nothing;

  update public.queue_lines
    set current_number = called_number, upcoming_number = next_number
    where id = line_record.id
    returning * into line_record;

  insert into public.queue_events (
    institution_id, queue_line_id, queue_number_id, event_type, event_number, created_by, details
  ) values (
    line_record.institution_id, line_record.id, called_record.id, 'called', called_number,
    auth.uid(), jsonb_build_object('advanced_after', p_status, 'previous_number', number_record.number)
  );

  return jsonb_build_object('number', to_jsonb(number_record), 'line', to_jsonb(line_record));
end;
$$;


ALTER FUNCTION "public"."queue_mark_number_and_call_next"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") RETURNS "public"."queue_events"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_line public.queue_lines%rowtype;
  v_number public.queue_numbers%rowtype;
  v_event public.queue_events%rowtype;
begin
  select * into v_line from public.queue_lines where id = p_queue_line_id;
  if not found or not public.queue_staff_can_manage(v_line.institution_id) then
    raise exception 'You do not have permission to notify this queue number.';
  end if;
  if v_line.status in ('closed', 'reset') then
    raise exception 'This queue line is not active for notifications.';
  end if;

  select * into v_number
  from public.queue_numbers
  where queue_line_id = v_line.id
    and upper(regexp_replace(number, '[[:space:]-]', '', 'g')) =
        upper(regexp_replace(trim(p_number), '[[:space:]-]', '', 'g'))
  limit 1;
  if not found then
    raise exception 'Queue number % was not found in this queue line.', trim(p_number);
  end if;
  if v_number.status in ('completed', 'cancelled') then
    raise exception 'Queue number % is already % and cannot be notified.', v_number.number, v_number.status;
  end if;

  insert into public.queue_events (
    institution_id, queue_line_id, queue_number_id, event_type, event_number,
    created_by, details
  ) values (
    v_line.institution_id, v_line.id, v_number.id, 'notified', v_number.number,
    auth.uid(), '{"source":"staff_console","kind":"call_again"}'::jsonb
  ) returning * into v_event;
  return v_event;
end;
$$;


ALTER FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.institutions institution
    where institution.id = p_institution_id
      and institution.account_user_id = (select auth.uid())
  ) or p_institution_id = public.current_staff_institution_id();
$$;


ALTER FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_track_waiting_number"("p_queue_line_id" "uuid", "p_number" "text") RETURNS "public"."queue_numbers"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_line public.queue_lines%rowtype;
  v_value integer;
  v_prefix text;
  v_input_prefix text;
  v_number text;
  v_result public.queue_numbers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required to track a queue number';
  end if;

  select * into v_line
  from public.queue_lines
  where id = p_queue_line_id and status = 'active';
  if not found then
    raise exception 'This queue line is no longer active';
  end if;

  v_value := nullif(substring(trim(p_number) from '([0-9]+)$'), '')::integer;
  v_prefix := upper(regexp_replace(coalesce(v_line.prefix, ''), '[[:space:]-]', '', 'g'));
  v_input_prefix := upper(regexp_replace(
    regexp_replace(trim(p_number), '[0-9]+$', ''),
    '[[:space:]-]', '', 'g'
  ));
  if v_value is null or v_value < 1
     or (v_line.max_tracking_number is not null and v_value > v_line.max_tracking_number)
     or v_input_prefix <> v_prefix
  then
    raise exception 'Queue number is outside this line''s valid range';
  end if;

  v_number := case when v_prefix = '' then lpad(v_value::text, 3, '0')
                   else v_prefix || '-' || lpad(v_value::text, 3, '0') end;

  select * into v_result
  from public.queue_numbers
  where queue_line_id = p_queue_line_id and number = v_number
  for update;
  if found then
    if v_result.status = 'waiting' and v_result.traveler_id is null then
      update public.queue_numbers
      set traveler_id = auth.uid(), updated_at = now()
      where id = v_result.id
      returning * into v_result;
    end if;
    return v_result;
  end if;

  insert into public.queue_numbers (
    queue_line_id, institution_id, number, status, traveler_id
  ) values (
    v_line.id, v_line.institution_id, v_number, 'waiting', auth.uid()
  ) returning * into v_result;
  return v_result;
exception when unique_violation then
  select * into v_result
  from public.queue_numbers
  where queue_line_id = p_queue_line_id and number = v_number;
  return v_result;
end;
$_$;


ALTER FUNCTION "public"."queue_track_waiting_number"("p_queue_line_id" "uuid", "p_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_feature_usage"("p_feature_key" "text", "p_event" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    event_time TIMESTAMPTZ := NOW();
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'An authenticated user is required.';
    END IF;

    IF p_feature_key NOT IN (
        'sign_translate',
        'speech_to_sign',
        'two_way_dialogue',
        'sign_dictionary',
        'request_help',
        'queue_tracking',
        'announcements',
        'gps_location',
        'sos'
    ) THEN
        RAISE EXCEPTION 'Unknown feature key: %', p_feature_key;
    END IF;

    IF p_event NOT IN ('opened', 'completed') THEN
        RAISE EXCEPTION 'Unknown feature event: %', p_event;
    END IF;

    INSERT INTO public.user_feature_guidance (
        user_id,
        feature_key,
        first_opened_at,
        first_completed_at
    ) VALUES (
        auth.uid(),
        p_feature_key,
        CASE WHEN p_event IN ('opened', 'completed') THEN event_time END,
        CASE WHEN p_event = 'completed' THEN event_time END
    )
    ON CONFLICT (user_id, feature_key) DO UPDATE SET
        first_opened_at = COALESCE(
            user_feature_guidance.first_opened_at,
            CASE WHEN p_event IN ('opened', 'completed') THEN event_time END
        ),
        first_completed_at = COALESCE(
            user_feature_guidance.first_completed_at,
            CASE WHEN p_event = 'completed' THEN event_time END
        ),
        updated_at = event_time;
END;
$$;


ALTER FUNCTION "public"."record_feature_usage"("p_feature_key" "text", "p_event" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_announcement_statuses"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.announcements
  set status = case
    when expires_at is not null and expires_at <= now() then 'expired'
    when published_at is not null and published_at > now() then 'scheduled'
    else 'active'
  end,
  updated_at = now()
  where status <> 'withdrawn'
    and status is distinct from case
      when expires_at is not null and expires_at <= now() then 'expired'
      when published_at is not null and published_at > now() then 'scheduled'
      else 'active'
    end;
end;
$$;


ALTER FUNCTION "public"."refresh_announcement_statuses"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_emergency_contact_verification_on_email_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.email is distinct from old.email then
    new.is_verified := false;
    new.is_primary := false;

    delete from public.emergency_contact_verifications
    where contact_id = old.id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."reset_emergency_contact_verification_on_email_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_institution_staff_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_institution_staff_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_institutions_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_institutions_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_primary_emergency_contact"("contact_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (
    select 1
    from public.emergency_contacts
    where id = contact_id
      and user_id = (select auth.uid())
  ) then
    raise exception 'Emergency contact not found';
  end if;

  if not exists (
    select 1
    from public.emergency_contacts
    where id = contact_id
      and user_id = (select auth.uid())
      and is_verified = true
  ) then
    raise exception
      'Only verified emergency contacts can be primary';
  end if;

  update public.emergency_contacts
  set
    is_primary = false,
    updated_at = now()
  where user_id = (select auth.uid())
    and is_primary = true;

  update public.emergency_contacts
  set
    is_primary = true,
    updated_at = now()
  where id = contact_id
    and user_id = (select auth.uid());
end;
$$;


ALTER FUNCTION "public"."set_primary_emergency_contact"("contact_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_service_areas_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin new.updated_at = now(); return new; end;
$$;


ALTER FUNCTION "public"."set_service_areas_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_assistance_staff_availability"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  -- When assigned to an in-progress assistance request, mark staff as 'assigned'
  if new.assigned_staff_id is not null and new.status = 'in_progress' then
    update public.institution_staff
      set status = 'assigned'
      where id = new.assigned_staff_id
        and status is distinct from 'assigned';
  end if;

  -- When request is resolved, completed, cancelled, or reassigned
  if tg_op = 'UPDATE' then
    if old.assigned_staff_id is not null and old.status = 'in_progress'
      and (new.status in ('resolved', 'completed', 'cancelled', 'closed') or new.assigned_staff_id is distinct from old.assigned_staff_id) then
      update public.institution_staff s
        set status = 'free'
        where s.id = old.assigned_staff_id
          and s.status = 'assigned'
          and not exists (
            select 1 from public.assistance_requests ar
            where ar.assigned_staff_id = s.id
              and ar.status = 'in_progress'
              and ar.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
          )
          and not exists (
            select 1 from public.sos_requests sr
            where sr.assigned_staff_id = s.id
              and sr.status in ('assigned', 'en_route')
          );
    end if;
  end if;

  -- When request is deleted
  if tg_op = 'DELETE' then
    if old.assigned_staff_id is not null and old.status = 'in_progress' then
      update public.institution_staff s
        set status = 'free'
        where s.id = old.assigned_staff_id
          and s.status = 'assigned'
          and not exists (
            select 1 from public.assistance_requests ar
            where ar.assigned_staff_id = s.id
              and ar.status = 'in_progress'
              and ar.id <> old.id
          )
          and not exists (
            select 1 from public.sos_requests sr
            where sr.assigned_staff_id = s.id
              and sr.status in ('assigned', 'en_route')
          );
    end if;
    return old;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."sync_assistance_staff_availability"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_institution_email_verification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if new.email_confirmed_at is not null
     and old.email_confirmed_at is null then
    update public.institutions
    set verification_status = 'email_verified'
    where account_user_id = new.id;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_institution_email_verification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_sos_staff_availability"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.assigned_staff_id is not null and new.status in ('assigned', 'en_route') then
    update public.institution_staff
      set status = 'assigned'
      where id = new.assigned_staff_id and institution_id = new.institution_id
        and status is distinct from 'assigned';
  end if;

  if tg_op = 'UPDATE' then
    if old.assigned_staff_id is not null and old.status in ('assigned', 'en_route')
      and (new.status = 'resolved' or new.assigned_staff_id is distinct from old.assigned_staff_id) then
      update public.institution_staff s set status = 'free'
        where s.id = old.assigned_staff_id and s.institution_id = old.institution_id
          and s.status = 'assigned'
          and not exists (select 1 from public.sos_requests r
            where r.assigned_staff_id = s.id and r.status in ('assigned', 'en_route'))
          and not exists (select 1 from public.assistance_requests ar
            where ar.assigned_staff_id = s.id and ar.status = 'in_progress');
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_sos_staff_availability"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."travelease_handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if new.raw_user_meta_data ->> 'account_type' = 'institution'
     or exists (
       select 1 from public.institutions
       where account_user_id = new.id
     ) then
    return new;
  end if;

  insert into public.user_profiles (
    id,
    full_name,
    nationality,
    profile_completed
  ) values (
    new.id,
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'nationality'), ''),
    true
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, user_profiles.full_name),
    nationality = coalesce(excluded.nationality, user_profiles.nationality),
    profile_completed = true,
    updated_at = now();

  return new;
end;
$$;


ALTER FUNCTION "public"."travelease_handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_staff_name"("p_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 100 then
    raise exception 'Name must be between 1 and 100 characters';
  end if;
  update public.institution_staff s set name = btrim(p_name)
    where s.auth_user_id = auth.uid() and s.role = 'staff' and s.active
      and exists (select 1 from public.institutions i where i.id = s.institution_id and i.active);
  if not found then raise exception 'This account does not have access to the institution portal.'; end if;
end;
$$;


ALTER FUNCTION "public"."update_my_staff_name"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_sos_progress"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'UPDATE' then
    if new.traveller_id is distinct from old.traveller_id
      or new.institution_id is distinct from old.institution_id
      or new.service_area_id is distinct from old.service_area_id
      or new.triggered_at is distinct from old.triggered_at then
      raise exception 'SOS ownership, service area and trigger time are immutable';
    end if;
    if new.status is distinct from old.status and not (
      (old.status = 'sent' and new.status = 'acknowledged') or
      (old.status = 'acknowledged' and new.status in ('assigned', 'resolved')) or
      (old.status = 'assigned' and new.status in ('en_route', 'resolved')) or
      (old.status = 'en_route' and new.status = 'resolved')
    ) then
      raise exception 'Invalid SOS transition: % -> %', old.status, new.status;
    end if;
    if new.assigned_staff_id is distinct from old.assigned_staff_id
      and new.assigned_staff_id is not null
      and new.status not in ('assigned', 'en_route') then
      raise exception 'Staff can only be assigned to an ongoing acknowledged SOS';
    end if;
  end if;
  if tg_op = 'INSERT' and not exists (
    select 1 from public.service_areas a where a.id = new.service_area_id
      and a.institution_id = new.institution_id and a.active = true
  ) then raise exception 'SOS service area does not belong to the institution'; end if;
  if new.assigned_staff_id is not null and (
    tg_op = 'INSERT' or new.assigned_staff_id is distinct from old.assigned_staff_id
  ) and not exists (
    select 1 from public.institution_staff s where s.id = new.assigned_staff_id
      and s.institution_id = new.institution_id and s.active = true
  ) then raise exception 'Assigned staff must be active in the SOS institution'; end if;
  -- Allow a historical assignee to be deleted (FK SET NULL); require an assignee
  -- when entering the assigned/on-the-way stages.
  if new.status in ('assigned', 'en_route') and new.assigned_staff_id is null
    and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    raise exception 'Assign a staff member before advancing the SOS';
  end if;
  if tg_op = 'UPDATE' then
    new.acknowledged_at := old.acknowledged_at;
    new.resolved_at := old.resolved_at;
    if old.status = 'sent' and new.status = 'acknowledged' then
      new.acknowledged_at := coalesce(old.acknowledged_at, now());
    end if;
    if old.status <> 'resolved' and new.status = 'resolved' then
      new.resolved_at := now();
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."validate_sos_progress"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."withdraw_announcements_for_inactive_area"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.active and not new.active then
    update public.announcements
    set status = 'withdrawn', updated_at = now()
    where service_area_id = new.id and status <> 'withdrawn';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."withdraw_announcements_for_inactive_area"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."accessibility_issue_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_code" character varying(32) NOT NULL,
    "user_id" "uuid",
    "traveler_name" character varying(100) DEFAULT 'Anonymous'::character varying,
    "issue_type" character varying(50) NOT NULL,
    "venue_name" character varying(100) NOT NULL,
    "location_zone" character varying(100) NOT NULL,
    "description" "text" NOT NULL,
    "severity" character varying(20) DEFAULT 'moderate'::character varying NOT NULL,
    "status" character varying(20) DEFAULT 'reported'::character varying NOT NULL,
    "admin_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "analytics_consent" boolean DEFAULT false NOT NULL,
    "photo_url" "text"
);


ALTER TABLE "public"."accessibility_issue_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."accessibility_preferences" (
    "user_id" "uuid" NOT NULL,
    "caption_size" double precision DEFAULT 16 NOT NULL,
    "caption_speed" double precision DEFAULT 1 NOT NULL,
    "high_contrast" boolean DEFAULT false NOT NULL,
    "full_screen_alerts" boolean DEFAULT true NOT NULL,
    "vibration" boolean DEFAULT true NOT NULL,
    "vibration_strength" "text" DEFAULT 'medium'::"text" NOT NULL,
    "flash_alerts" boolean DEFAULT false NOT NULL,
    "recognition_confidence" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notifications_enabled" boolean DEFAULT true NOT NULL,
    "notification_announcements" boolean DEFAULT true NOT NULL,
    "notification_queue" boolean DEFAULT true NOT NULL,
    "notification_messages" boolean DEFAULT true NOT NULL,
    CONSTRAINT "accessibility_preferences_caption_size_check" CHECK ((("caption_size" >= (12)::double precision) AND ("caption_size" <= (28)::double precision))),
    CONSTRAINT "accessibility_preferences_caption_speed_check" CHECK ((("caption_speed" >= (0.5)::double precision) AND ("caption_speed" <= (2)::double precision))),
    CONSTRAINT "accessibility_preferences_vibration_strength_check" CHECK (("vibration_strength" = ANY (ARRAY['light'::"text", 'medium'::"text", 'strong'::"text"])))
);


ALTER TABLE "public"."accessibility_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."analytics_daily_metrics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "metric_date" "date" NOT NULL,
    "venue_name" character varying(100) NOT NULL,
    "location_zone" character varying(100) NOT NULL,
    "total_requests" integer DEFAULT 0 NOT NULL,
    "resolved_requests" integer DEFAULT 0 NOT NULL,
    "total_barriers_reported" integer DEFAULT 0 NOT NULL,
    "avg_response_time_sec" integer,
    "avg_resolution_time_sec" integer,
    "avg_user_satisfaction" numeric(3,2)
);


ALTER TABLE "public"."analytics_daily_metrics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."announcements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "message_en" "text" NOT NULL,
    "announcement_type" "text",
    "priority" "text" DEFAULT 'normal'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "published_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "reach_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "auto_translated" boolean DEFAULT false NOT NULL,
    "scheduled_publish_at" timestamp with time zone,
    "service_area_id" "uuid",
    CONSTRAINT "announcements_announcement_type_check" CHECK (("length"("announcement_type") < 160)),
    CONSTRAINT "announcements_check" CHECK ((("expires_at" IS NULL) OR ("published_at" IS NULL) OR ("expires_at" > "published_at"))),
    CONSTRAINT "announcements_message_en_check" CHECK ((("char_length"(TRIM(BOTH FROM "message_en")) >= 1) AND ("char_length"(TRIM(BOTH FROM "message_en")) <= 2000))),
    CONSTRAINT "announcements_priority_check" CHECK (("priority" = ANY (ARRAY['low'::"text", 'normal'::"text", 'high'::"text", 'urgent'::"text"]))),
    CONSTRAINT "announcements_reach_count_check" CHECK (("reach_count" >= 0)),
    CONSTRAINT "announcements_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'scheduled'::"text", 'expired'::"text", 'withdrawn'::"text"]))),
    CONSTRAINT "announcements_title_check" CHECK ((("char_length"(TRIM(BOTH FROM "title")) >= 1) AND ("char_length"(TRIM(BOTH FROM "title")) <= 160))),
    CONSTRAINT "announcements_translations_is_object" CHECK (("jsonb_typeof"("translations") = 'object'::"text"))
);


ALTER TABLE "public"."announcements" OWNER TO "postgres";


COMMENT ON COLUMN "public"."announcements"."scheduled_publish_at" IS 'Planned publish time; travellers see the announcement once published_at passes. Null means it was published immediately.';



COMMENT ON COLUMN "public"."announcements"."service_area_id" IS 'Optional target service area. Null broadcasts to every service area in the institution.';



CREATE TABLE IF NOT EXISTS "public"."assistance_chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "sender_type" character varying(20) NOT NULL,
    "sender_id" "uuid",
    "sender_name" character varying(100) NOT NULL,
    "content" "text" NOT NULL,
    "message_type" character varying(30) DEFAULT 'text'::character varying NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."assistance_chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assistance_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_code" character varying(32) NOT NULL,
    "user_id" "uuid",
    "traveler_name" character varying(100) NOT NULL,
    "preferred_communication" character varying(50) DEFAULT 'in_app_chat'::character varying NOT NULL,
    "category" character varying(50) NOT NULL,
    "venue_name" character varying(100) NOT NULL,
    "location_zone" character varying(100) NOT NULL,
    "description" "text" NOT NULL,
    "urgency" character varying(20) DEFAULT 'medium'::character varying NOT NULL,
    "status" character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "assigned_staff_id" "uuid",
    "assigned_staff_name" character varying(100) DEFAULT 'Unassigned'::character varying,
    "share_location" boolean DEFAULT true NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "resolution_outcome" character varying(30),
    "user_rating" numeric(3,2),
    "user_feedback_comment" "text",
    "response_time_seconds" integer,
    "resolution_time_seconds" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "is_escalated" boolean DEFAULT false,
    "escalated_at" timestamp with time zone,
    "analytics_consent" boolean DEFAULT false,
    "acknowledged_at" timestamp with time zone
);


ALTER TABLE "public"."assistance_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communication_dialogue_messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "sender_role" "text" NOT NULL,
    "sender_name" "text" NOT NULL,
    "original_text" "text" NOT NULL,
    "translated_text" "text" NOT NULL,
    "source_language" "text" NOT NULL,
    "target_language" "text" NOT NULL,
    "input_modality" "text" NOT NULL,
    "ai_confidence_score" numeric(4,3) DEFAULT 0.950,
    "is_corrected" boolean DEFAULT false,
    "corrected_text" "text",
    "audio_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "communication_dialogue_messages_input_modality_check" CHECK (("input_modality" = ANY (ARRAY['sign_to_text'::"text", 'speech_to_text'::"text", 'typed_text'::"text", 'quick_phrase'::"text"]))),
    CONSTRAINT "communication_dialogue_messages_sender_role_check" CHECK (("sender_role" = ANY (ARRAY['traveler'::"text", 'staff'::"text", 'system'::"text"])))
);


ALTER TABLE "public"."communication_dialogue_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communication_dialogue_sessions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "session_code" "text" NOT NULL,
    "traveler_id" "uuid",
    "traveler_name" "text" DEFAULT 'Deaf Traveler'::"text" NOT NULL,
    "staff_name" "text" DEFAULT 'Staff / Hearing Individual'::"text" NOT NULL,
    "traveler_sign_language" "text" DEFAULT 'BIM'::"text" NOT NULL,
    "source_language" "text" DEFAULT 'en'::"text" NOT NULL,
    "target_language" "text" DEFAULT 'ms'::"text" NOT NULL,
    "speech_playback_speed" numeric(3,2) DEFAULT 1.00,
    "speech_playback_volume" numeric(3,2) DEFAULT 1.00,
    "speech_voice_gender" "text" DEFAULT 'female'::"text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "ended_at" timestamp with time zone,
    CONSTRAINT "communication_dialogue_sessions_speech_voice_gender_check" CHECK (("speech_voice_gender" = ANY (ARRAY['female'::"text", 'male'::"text", 'neutral'::"text"]))),
    CONSTRAINT "communication_dialogue_sessions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."communication_dialogue_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communication_quick_phrases" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "category" "text" NOT NULL,
    "text_en" "text" NOT NULL,
    "text_ms" "text" NOT NULL,
    "text_zh" "text" NOT NULL,
    "icon_name" "text" DEFAULT 'chat'::"text",
    "display_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."communication_quick_phrases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communication_saved_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid",
    "log_title" "text" NOT NULL,
    "translation_type" "text" NOT NULL,
    "summary" "text",
    "full_transcript" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "message_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "communication_saved_logs_translation_type_check" CHECK (("translation_type" = ANY (ARRAY['two_way_dialogue'::"text", 'sign_to_text'::"text", 'speech_to_sign'::"text"])))
);


ALTER TABLE "public"."communication_saved_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_communication_cards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "hearing_impairment_note" "text" DEFAULT 'I am deaf / hard of hearing'::"text" NOT NULL,
    "preferred_communication_method" "text" DEFAULT 'written_text'::"text" NOT NULL,
    "sign_language" "text" DEFAULT 'bim'::"text" NOT NULL,
    "languages" "text" DEFAULT ''::"text" NOT NULL,
    "blood_type" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "allergy_information" "text" DEFAULT ''::"text" NOT NULL,
    "medical_notes" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "emergency_communication_card_preferred_communication_meth_check" CHECK (("preferred_communication_method" = ANY (ARRAY['written_text'::"text", 'sign_language'::"text", 'speech_to_text'::"text", 'combined'::"text"]))),
    CONSTRAINT "emergency_communication_cards_blood_type_check" CHECK (("blood_type" = ANY (ARRAY['unknown'::"text", 'A+'::"text", 'A-'::"text", 'B+'::"text", 'B-'::"text", 'AB+'::"text", 'AB-'::"text", 'O+'::"text", 'O-'::"text"]))),
    CONSTRAINT "emergency_communication_cards_sign_language_check" CHECK (("sign_language" = ANY (ARRAY['bim'::"text", 'asl'::"text", 'none'::"text"])))
);


ALTER TABLE "public"."emergency_communication_cards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_contact_verifications" (
    "contact_id" "uuid" NOT NULL,
    "otp_hash" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_sent_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "emergency_contact_verifications_attempt_count_check" CHECK (("attempt_count" >= 0))
);


ALTER TABLE "public"."emergency_contact_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "relationship" "text" NOT NULL,
    "phone_number" "text" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_verified" boolean DEFAULT false NOT NULL,
    "verification_code" "text",
    "verification_expires_at" timestamp with time zone,
    "email" "text",
    CONSTRAINT "emergency_contacts_email_format" CHECK ((("email" IS NULL) OR ("email" ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::"text"))),
    CONSTRAINT "emergency_contacts_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 1) AND ("char_length"(TRIM(BOTH FROM "name")) <= 100))),
    CONSTRAINT "emergency_contacts_phone_number_check" CHECK ((("char_length"(TRIM(BOTH FROM "phone_number")) >= 1) AND ("char_length"(TRIM(BOTH FROM "phone_number")) <= 30))),
    CONSTRAINT "emergency_contacts_primary_requires_verification" CHECK ((("is_primary" = false) OR ("is_verified" = true))),
    CONSTRAINT "emergency_contacts_relationship_check" CHECK ((("char_length"(TRIM(BOTH FROM "relationship")) >= 1) AND ("char_length"(TRIM(BOTH FROM "relationship")) <= 100))),
    CONSTRAINT "emergency_contacts_verification_code_format" CHECK ((("verification_code" IS NULL) OR ("verification_code" ~ '^[0-9]{6}$'::"text")))
);


ALTER TABLE "public"."emergency_contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."generated_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "report_title" "text" NOT NULL,
    "report_type" "text" NOT NULL,
    "date_from" "date" NOT NULL,
    "date_to" "date" NOT NULL,
    "zone_filter" "text" DEFAULT 'all'::"text" NOT NULL,
    "format" "text" NOT NULL,
    "data_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "generated_reports_format_check" CHECK (("format" = ANY (ARRAY['pdf'::"text", 'csv'::"text"]))),
    CONSTRAINT "generated_reports_report_type_check" CHECK (("report_type" = ANY (ARRAY['accessibility'::"text", 'assistance_performance'::"text", 'queue_service'::"text", 'communication_usage'::"text", 'users'::"text"])))
);


ALTER TABLE "public"."generated_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institution_staff" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid",
    "name" character varying(255) NOT NULL,
    "role" character varying(100) DEFAULT 'Support Staff'::character varying,
    "department" character varying(100),
    "contact_number" character varying(50),
    "status" character varying(50) DEFAULT 'free'::character varying NOT NULL,
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "auth_user_id" "uuid",
    "email" "text",
    "active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "institution_staff_availability_check" CHECK ((("status")::"text" = ANY ((ARRAY['free'::character varying, 'assigned'::character varying])::"text"[])))
);


ALTER TABLE "public"."institution_staff" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institutions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "branch" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "account_user_id" "uuid" NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "location_match_radius_m" integer DEFAULT 500 NOT NULL,
    "institution_type" "text" NOT NULL,
    "official_contact" "text" NOT NULL,
    "service_address" "text" NOT NULL,
    "registration_document_path" "text",
    "verification_status" "text" DEFAULT 'email_pending'::"text" NOT NULL,
    CONSTRAINT "institutions_institution_type_check" CHECK (("institution_type" = ANY (ARRAY['airport_transport'::"text", 'hotel_hospitality'::"text", 'tourist_attraction'::"text", 'healthcare'::"text", 'government'::"text", 'other'::"text"]))),
    CONSTRAINT "institutions_verification_status_check" CHECK (("verification_status" = ANY (ARRAY['email_pending'::"text", 'email_verified'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."institutions" OWNER TO "postgres";


COMMENT ON COLUMN "public"."institutions"."latitude" IS 'WGS84 latitude of the institution venue used to match a traveller''s detected location (FR-M2-02).';



COMMENT ON COLUMN "public"."institutions"."longitude" IS 'WGS84 longitude of the institution venue used to match a traveller''s detected location (FR-M2-02).';



COMMENT ON COLUMN "public"."institutions"."location_match_radius_m" IS 'Radius in metres around the stored coordinates that still counts as being at this institution when starting a venue session.';



CREATE TABLE IF NOT EXISTS "public"."service_areas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "radius_m" integer NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "service_areas_address_check" CHECK ((("address" IS NULL) OR ("char_length"("address") <= 500))),
    CONSTRAINT "service_areas_latitude_check" CHECK ((("latitude" >= ('-90'::integer)::double precision) AND ("latitude" <= (90)::double precision))),
    CONSTRAINT "service_areas_longitude_check" CHECK ((("longitude" >= ('-180'::integer)::double precision) AND ("longitude" <= (180)::double precision))),
    CONSTRAINT "service_areas_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120))),
    CONSTRAINT "service_areas_radius_check" CHECK ((("radius_m" >= 1) AND ("radius_m" <= 50000)))
);


ALTER TABLE "public"."service_areas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_asset_feedback" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "phrase_id" "uuid",
    "sign_language_id" "text",
    "issue_type" "text" NOT NULL,
    "description" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "sign_asset_feedback_issue_type_check" CHECK (("issue_type" = ANY (ARRAY['unclear_gesture'::"text", 'broken_video'::"text", 'incorrect_gloss'::"text", 'incorrect_translation'::"text", 'other'::"text"]))),
    CONSTRAINT "sign_asset_feedback_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'reviewed'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."sign_asset_feedback" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_categories" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "icon_name" "text" NOT NULL,
    "display_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sign_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_dictionary_phrases" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "category_id" "text" NOT NULL,
    "phrase_en" "text" NOT NULL,
    "phrase_ms" "text" NOT NULL,
    "phrase_zh" "text" NOT NULL,
    "gloss_asl" "text",
    "gloss_bim" "text",
    "gloss_csl" "text",
    "scenario" "text",
    "step_instructions" "jsonb" DEFAULT '[]'::"jsonb",
    "related_phrase_ids" "text"[] DEFAULT ARRAY[]::"text"[],
    "is_verified" boolean DEFAULT true,
    "view_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sign_dictionary_phrases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_languages" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "native_name" "text" NOT NULL,
    "country_code" "text" NOT NULL,
    "country_name" "text" NOT NULL,
    "primary_spoken_language" "text" NOT NULL,
    "description" "text",
    "flag_emoji" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sign_languages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_media_assets" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "phrase_id" "uuid" NOT NULL,
    "sign_language_id" "text" NOT NULL,
    "perspective" "text" DEFAULT 'front'::"text" NOT NULL,
    "video_url" "text" NOT NULL,
    "animation_url" "text",
    "thumbnail_url" "text",
    "duration_seconds" numeric(4,2) DEFAULT 3.00,
    "frame_count" integer DEFAULT 90,
    "fps" integer DEFAULT 30,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "sign_media_assets_perspective_check" CHECK (("perspective" = ANY (ARRAY['front'::"text", 'side'::"text", 'top'::"text"])))
);


ALTER TABLE "public"."sign_media_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sign_translations_history" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "sign_language_id" "text" NOT NULL,
    "predicted_text" "text" NOT NULL,
    "confirmed_text" "text" NOT NULL,
    "confidence_score" numeric(4,3) NOT NULL,
    "is_edited" boolean DEFAULT false,
    "audio_played" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sign_translations_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sla_configs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "zone_id" "uuid",
    "response_limit_minutes" integer DEFAULT 5 NOT NULL,
    "resolution_limit_minutes" integer DEFAULT 60 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sla_configs_resolution_limit_minutes_check" CHECK (("resolution_limit_minutes" > 0)),
    CONSTRAINT "sla_configs_response_limit_minutes_check" CHECK (("response_limit_minutes" > 0))
);


ALTER TABLE "public"."sla_configs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sos_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "traveller_id" "uuid" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "service_area_id" "uuid" NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "triggered_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "acknowledged_at" timestamp with time zone,
    "resolved_at" timestamp with time zone,
    "assigned_staff_id" "uuid",
    CONSTRAINT "sos_requests_latitude_check" CHECK ((("latitude" >= ('-90'::integer)::double precision) AND ("latitude" <= (90)::double precision))),
    CONSTRAINT "sos_requests_longitude_check" CHECK ((("longitude" >= ('-180'::integer)::double precision) AND ("longitude" <= (180)::double precision))),
    CONSTRAINT "sos_requests_status_check" CHECK (("status" = ANY (ARRAY['sent'::"text", 'acknowledged'::"text", 'assigned'::"text", 'en_route'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."sos_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."traveler_live_locations" (
    "session_id" "uuid" NOT NULL,
    "session_type" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "accuracy_m" double precision,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "traveler_live_locations_session_type_check" CHECK (("session_type" = ANY (ARRAY['assistance'::"text", 'sos'::"text"])))
);


ALTER TABLE "public"."traveler_live_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."traveller_sos_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "traveller_id" "uuid" NOT NULL,
    "triggered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "sos_request_id" "uuid",
    "institution_name" "text",
    "service_area_name" "text",
    "institution_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "contact_name" "text",
    "contact_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "contact_attempted_at" timestamp with time zone,
    "institution_attempted_at" timestamp with time zone,
    CONSTRAINT "traveller_sos_events_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'ended'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."traveller_sos_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_favorite_phrases" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "phrase_id" "uuid" NOT NULL,
    "order_index" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_favorite_phrases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_feature_guidance" (
    "user_id" "uuid" NOT NULL,
    "feature_key" "text" NOT NULL,
    "first_opened_at" timestamp with time zone,
    "first_completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_feature_guidance_feature_key_check" CHECK (("feature_key" = ANY (ARRAY['sign_translate'::"text", 'speech_to_sign'::"text", 'two_way_dialogue'::"text", 'sign_dictionary'::"text", 'request_help'::"text", 'queue_tracking'::"text", 'announcements'::"text", 'gps_location'::"text", 'sos'::"text"])))
);


ALTER TABLE "public"."user_feature_guidance" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "nationality" "text",
    "profile_completed" boolean DEFAULT false NOT NULL,
    "avatar_url" "text"
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."venue_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "traveler_id" "uuid" NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "service_area_id" "uuid",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."venue_sessions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."accessibility_issue_reports"
    ADD CONSTRAINT "accessibility_issue_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."accessibility_issue_reports"
    ADD CONSTRAINT "accessibility_issue_reports_report_code_key" UNIQUE ("report_code");



ALTER TABLE ONLY "public"."accessibility_preferences"
    ADD CONSTRAINT "accessibility_preferences_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."analytics_daily_metrics"
    ADD CONSTRAINT "analytics_daily_metrics_metric_date_venue_name_location_zon_key" UNIQUE ("metric_date", "venue_name", "location_zone");



ALTER TABLE ONLY "public"."analytics_daily_metrics"
    ADD CONSTRAINT "analytics_daily_metrics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assistance_chat_messages"
    ADD CONSTRAINT "assistance_chat_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assistance_requests"
    ADD CONSTRAINT "assistance_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assistance_requests"
    ADD CONSTRAINT "assistance_requests_request_code_key" UNIQUE ("request_code");



ALTER TABLE ONLY "public"."communication_dialogue_messages"
    ADD CONSTRAINT "communication_dialogue_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."communication_dialogue_sessions"
    ADD CONSTRAINT "communication_dialogue_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."communication_dialogue_sessions"
    ADD CONSTRAINT "communication_dialogue_sessions_session_code_key" UNIQUE ("session_code");



ALTER TABLE ONLY "public"."communication_quick_phrases"
    ADD CONSTRAINT "communication_quick_phrases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."communication_saved_logs"
    ADD CONSTRAINT "communication_saved_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emergency_communication_cards"
    ADD CONSTRAINT "emergency_communication_cards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emergency_communication_cards"
    ADD CONSTRAINT "emergency_communication_cards_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."emergency_contact_verifications"
    ADD CONSTRAINT "emergency_contact_verifications_pkey" PRIMARY KEY ("contact_id");



ALTER TABLE ONLY "public"."emergency_contacts"
    ADD CONSTRAINT "emergency_contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."generated_reports"
    ADD CONSTRAINT "generated_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."institution_staff"
    ADD CONSTRAINT "institution_staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."institutions"
    ADD CONSTRAINT "institutions_name_branch_key" UNIQUE ("name", "branch");



ALTER TABLE ONLY "public"."institutions"
    ADD CONSTRAINT "institutions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."queue_events"
    ADD CONSTRAINT "queue_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."queue_lines"
    ADD CONSTRAINT "queue_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."queue_numbers"
    ADD CONSTRAINT "queue_numbers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."queue_numbers"
    ADD CONSTRAINT "queue_numbers_queue_line_id_number_key" UNIQUE ("queue_line_id", "number");



ALTER TABLE ONLY "public"."service_areas"
    ADD CONSTRAINT "service_areas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_asset_feedback"
    ADD CONSTRAINT "sign_asset_feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_categories"
    ADD CONSTRAINT "sign_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_dictionary_phrases"
    ADD CONSTRAINT "sign_dictionary_phrases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_languages"
    ADD CONSTRAINT "sign_languages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_media_assets"
    ADD CONSTRAINT "sign_media_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sign_translations_history"
    ADD CONSTRAINT "sign_translations_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sla_configs"
    ADD CONSTRAINT "sla_configs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."traveler_live_locations"
    ADD CONSTRAINT "traveler_live_locations_pkey" PRIMARY KEY ("session_id");



ALTER TABLE ONLY "public"."traveller_sos_events"
    ADD CONSTRAINT "traveller_sos_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."traveller_sos_events"
    ADD CONSTRAINT "traveller_sos_events_traveller_id_triggered_at_key" UNIQUE ("traveller_id", "triggered_at");



ALTER TABLE ONLY "public"."user_favorite_phrases"
    ADD CONSTRAINT "user_favorite_phrases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_favorite_phrases"
    ADD CONSTRAINT "user_favorite_phrases_user_id_phrase_id_key" UNIQUE ("user_id", "phrase_id");



ALTER TABLE ONLY "public"."user_feature_guidance"
    ADD CONSTRAINT "user_feature_guidance_pkey" PRIMARY KEY ("user_id", "feature_key");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."venue_sessions"
    ADD CONSTRAINT "venue_sessions_pkey" PRIMARY KEY ("id");



CREATE INDEX "announcements_active_expiry_idx" ON "public"."announcements" USING "btree" ("institution_id", "expires_at") WHERE ("status" = 'active'::"text");



CREATE INDEX "announcements_active_idx" ON "public"."announcements" USING "btree" ("institution_id", "status", "expires_at") WHERE ("status" = 'active'::"text");



CREATE INDEX "announcements_institution_published_idx" ON "public"."announcements" USING "btree" ("institution_id", "published_at" DESC);



CREATE INDEX "announcements_service_area_id_idx" ON "public"."announcements" USING "btree" ("service_area_id");



CREATE UNIQUE INDEX "emergency_contacts_one_primary_per_user_idx" ON "public"."emergency_contacts" USING "btree" ("user_id") WHERE ("is_primary" = true);



CREATE INDEX "emergency_contacts_user_id_idx" ON "public"."emergency_contacts" USING "btree" ("user_id");



CREATE INDEX "idx_fav_user" ON "public"."user_favorite_phrases" USING "btree" ("user_id");



CREATE INDEX "idx_media_phrase_lang" ON "public"."sign_media_assets" USING "btree" ("phrase_id", "sign_language_id");



CREATE INDEX "idx_messages_session" ON "public"."communication_dialogue_messages" USING "btree" ("session_id", "created_at");



CREATE INDEX "idx_phrases_category" ON "public"."sign_dictionary_phrases" USING "btree" ("category_id");



CREATE INDEX "idx_phrases_text_en" ON "public"."sign_dictionary_phrases" USING "gin" ("to_tsvector"('"english"'::"regconfig", "phrase_en"));



CREATE INDEX "idx_saved_logs_user" ON "public"."communication_saved_logs" USING "btree" ("user_id", "translation_type");



CREATE INDEX "idx_user_feature_guidance_user_id" ON "public"."user_feature_guidance" USING "btree" ("user_id");



CREATE UNIQUE INDEX "institution_staff_auth_user_id_uidx" ON "public"."institution_staff" USING "btree" ("auth_user_id") WHERE ("auth_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "institution_staff_institution_email_uidx" ON "public"."institution_staff" USING "btree" ("institution_id", "lower"("email")) WHERE ("email" IS NOT NULL);



CREATE INDEX "institution_staff_institution_id_idx" ON "public"."institution_staff" USING "btree" ("institution_id");



CREATE UNIQUE INDEX "institutions_account_user_id_idx" ON "public"."institutions" USING "btree" ("account_user_id") WHERE ("account_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "institutions_account_user_id_key" ON "public"."institutions" USING "btree" ("account_user_id");



CREATE INDEX "queue_events_line_created_idx" ON "public"."queue_events" USING "btree" ("queue_line_id", "created_at" DESC);



CREATE UNIQUE INDEX "queue_lines_institution_name_nonreset_key" ON "public"."queue_lines" USING "btree" ("institution_id", "lower"("name")) WHERE ("status" <> 'reset'::"text");



CREATE UNIQUE INDEX "queue_lines_institution_prefix_nonreset_key" ON "public"."queue_lines" USING "btree" ("institution_id", "lower"("prefix")) WHERE ("status" <> 'reset'::"text");



CREATE INDEX "queue_lines_institution_status_idx" ON "public"."queue_lines" USING "btree" ("institution_id", "status", "name");



CREATE INDEX "queue_lines_service_area_id_idx" ON "public"."queue_lines" USING "btree" ("service_area_id");



CREATE INDEX "queue_numbers_line_status_idx" ON "public"."queue_numbers" USING "btree" ("queue_line_id", "status", "created_at");



CREATE INDEX "queue_numbers_lookup_idx" ON "public"."queue_numbers" USING "btree" ("institution_id", "number");



CREATE INDEX "service_areas_active_idx" ON "public"."service_areas" USING "btree" ("active") WHERE ("active" = true);



CREATE UNIQUE INDEX "service_areas_institution_coverage_unique" ON "public"."service_areas" USING "btree" ("institution_id", "round"(("latitude")::numeric, 6), "round"(("longitude")::numeric, 6), "radius_m");



CREATE INDEX "service_areas_institution_id_idx" ON "public"."service_areas" USING "btree" ("institution_id");



CREATE UNIQUE INDEX "service_areas_institution_name_unique" ON "public"."service_areas" USING "btree" ("institution_id", "lower"(TRIM(BOTH FROM "regexp_replace"("name", '[[:space:]]+'::"text", ' '::"text", 'g'::"text"))));



CREATE UNIQUE INDEX "sla_configs_institution_zone_key" ON "public"."sla_configs" USING "btree" ("institution_id", COALESCE("zone_id", '00000000-0000-0000-0000-000000000000'::"uuid"));



CREATE INDEX "sos_requests_assigned_staff_idx" ON "public"."sos_requests" USING "btree" ("assigned_staff_id");



CREATE INDEX "sos_requests_institution_id_idx" ON "public"."sos_requests" USING "btree" ("institution_id", "triggered_at" DESC);



CREATE INDEX "sos_requests_service_area_id_idx" ON "public"."sos_requests" USING "btree" ("service_area_id");



CREATE INDEX "sos_requests_traveller_id_idx" ON "public"."sos_requests" USING "btree" ("traveller_id", "triggered_at" DESC);



CREATE INDEX "sos_requests_traveller_time_idx" ON "public"."sos_requests" USING "btree" ("traveller_id", "triggered_at" DESC);



CREATE INDEX "traveller_sos_events_owner_time" ON "public"."traveller_sos_events" USING "btree" ("traveller_id", "triggered_at" DESC);



CREATE INDEX "venue_sessions_active_area_idx" ON "public"."venue_sessions" USING "btree" ("service_area_id") WHERE ("ended_at" IS NULL);



CREATE UNIQUE INDEX "venue_sessions_traveler_unique" ON "public"."venue_sessions" USING "btree" ("traveler_id");



CREATE OR REPLACE TRIGGER "announcements_apply_status" BEFORE INSERT OR UPDATE OF "status", "published_at", "expires_at" ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."apply_announcement_status"();



CREATE OR REPLACE TRIGGER "announcements_set_updated_at" BEFORE UPDATE ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "enforce_announcement_service_area" BEFORE INSERT OR UPDATE OF "institution_id", "service_area_id" ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_service_area_assignment"();



CREATE OR REPLACE TRIGGER "enforce_queue_line_service_area" BEFORE INSERT OR UPDATE OF "institution_id", "service_area_id" ON "public"."queue_lines" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_service_area_assignment"();



CREATE OR REPLACE TRIGGER "enforce_sos_status_transition_trigger" BEFORE UPDATE OF "status" ON "public"."sos_requests" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sos_status_transition"();



CREATE OR REPLACE TRIGGER "institutions_set_updated_at" BEFORE UPDATE ON "public"."institutions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "prevent_institution_traveller_profile_trigger" BEFORE INSERT OR UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_institution_traveller_profile"();



CREATE OR REPLACE TRIGGER "queue_lines_set_updated_at" BEFORE UPDATE ON "public"."queue_lines" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "queue_numbers_closed_line_guard" BEFORE UPDATE ON "public"."queue_numbers" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_queue_line_not_closed"();



CREATE OR REPLACE TRIGGER "queue_numbers_set_updated_at" BEFORE UPDATE ON "public"."queue_numbers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "reset_emergency_contact_verification_on_email_change" BEFORE UPDATE OF "email" ON "public"."emergency_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."reset_emergency_contact_verification_on_email_change"();



CREATE OR REPLACE TRIGGER "service_area_delete_protection" BEFORE DELETE ON "public"."service_areas" FOR EACH ROW EXECUTE FUNCTION "public"."delete_service_area_dependents"();



CREATE OR REPLACE TRIGGER "service_area_inactive_withdraw_announcements" AFTER UPDATE OF "active" ON "public"."service_areas" FOR EACH ROW EXECUTE FUNCTION "public"."withdraw_announcements_for_inactive_area"();



CREATE OR REPLACE TRIGGER "set_institution_staff_updated_at_trigger" BEFORE UPDATE ON "public"."institution_staff" FOR EACH ROW EXECUTE FUNCTION "public"."set_institution_staff_updated_at"();



CREATE OR REPLACE TRIGGER "set_institutions_updated_at_trigger" BEFORE UPDATE ON "public"."institutions" FOR EACH ROW EXECUTE FUNCTION "public"."set_institutions_updated_at"();



CREATE OR REPLACE TRIGGER "set_service_areas_updated_at_trigger" BEFORE UPDATE ON "public"."service_areas" FOR EACH ROW EXECUTE FUNCTION "public"."set_service_areas_updated_at"();



CREATE OR REPLACE TRIGGER "sync_assistance_staff_availability_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."assistance_requests" FOR EACH ROW EXECUTE FUNCTION "public"."sync_assistance_staff_availability"();



CREATE OR REPLACE TRIGGER "sync_sos_staff_availability" AFTER INSERT OR UPDATE OF "status", "assigned_staff_id" ON "public"."sos_requests" FOR EACH ROW EXECUTE FUNCTION "public"."sync_sos_staff_availability"();



CREATE OR REPLACE TRIGGER "user_profiles_set_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "validate_sos_progress" BEFORE INSERT OR UPDATE ON "public"."sos_requests" FOR EACH ROW EXECUTE FUNCTION "public"."validate_sos_progress"();



ALTER TABLE ONLY "public"."accessibility_preferences"
    ADD CONSTRAINT "accessibility_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_service_area_id_fkey" FOREIGN KEY ("service_area_id") REFERENCES "public"."service_areas"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assistance_chat_messages"
    ADD CONSTRAINT "assistance_chat_messages_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."assistance_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."communication_dialogue_messages"
    ADD CONSTRAINT "communication_dialogue_messages_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."communication_dialogue_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."communication_dialogue_sessions"
    ADD CONSTRAINT "communication_dialogue_sessions_traveler_id_fkey" FOREIGN KEY ("traveler_id") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."communication_dialogue_sessions"
    ADD CONSTRAINT "communication_dialogue_sessions_traveler_sign_language_fkey" FOREIGN KEY ("traveler_sign_language") REFERENCES "public"."sign_languages"("id");



ALTER TABLE ONLY "public"."communication_saved_logs"
    ADD CONSTRAINT "communication_saved_logs_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."communication_dialogue_sessions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."communication_saved_logs"
    ADD CONSTRAINT "communication_saved_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emergency_communication_cards"
    ADD CONSTRAINT "emergency_communication_cards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emergency_contact_verifications"
    ADD CONSTRAINT "emergency_contact_verifications_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."emergency_contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emergency_contacts"
    ADD CONSTRAINT "emergency_contacts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."generated_reports"
    ADD CONSTRAINT "generated_reports_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."generated_reports"
    ADD CONSTRAINT "generated_reports_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."institution_staff"
    ADD CONSTRAINT "institution_staff_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."institution_staff"
    ADD CONSTRAINT "institution_staff_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."institutions"
    ADD CONSTRAINT "institutions_account_user_id_fkey" FOREIGN KEY ("account_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."queue_events"
    ADD CONSTRAINT "queue_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."queue_events"
    ADD CONSTRAINT "queue_events_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."queue_events"
    ADD CONSTRAINT "queue_events_queue_line_id_fkey" FOREIGN KEY ("queue_line_id") REFERENCES "public"."queue_lines"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."queue_events"
    ADD CONSTRAINT "queue_events_queue_number_id_fkey" FOREIGN KEY ("queue_number_id") REFERENCES "public"."queue_numbers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."queue_lines"
    ADD CONSTRAINT "queue_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."queue_lines"
    ADD CONSTRAINT "queue_lines_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."queue_lines"
    ADD CONSTRAINT "queue_lines_service_area_id_fkey" FOREIGN KEY ("service_area_id") REFERENCES "public"."service_areas"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."queue_numbers"
    ADD CONSTRAINT "queue_numbers_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."queue_numbers"
    ADD CONSTRAINT "queue_numbers_queue_line_id_fkey" FOREIGN KEY ("queue_line_id") REFERENCES "public"."queue_lines"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."queue_numbers"
    ADD CONSTRAINT "queue_numbers_traveler_id_fkey" FOREIGN KEY ("traveler_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_areas"
    ADD CONSTRAINT "service_areas_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sign_asset_feedback"
    ADD CONSTRAINT "sign_asset_feedback_phrase_id_fkey" FOREIGN KEY ("phrase_id") REFERENCES "public"."sign_dictionary_phrases"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sign_asset_feedback"
    ADD CONSTRAINT "sign_asset_feedback_sign_language_id_fkey" FOREIGN KEY ("sign_language_id") REFERENCES "public"."sign_languages"("id");



ALTER TABLE ONLY "public"."sign_asset_feedback"
    ADD CONSTRAINT "sign_asset_feedback_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sign_dictionary_phrases"
    ADD CONSTRAINT "sign_dictionary_phrases_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."sign_categories"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."sign_media_assets"
    ADD CONSTRAINT "sign_media_assets_phrase_id_fkey" FOREIGN KEY ("phrase_id") REFERENCES "public"."sign_dictionary_phrases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sign_media_assets"
    ADD CONSTRAINT "sign_media_assets_sign_language_id_fkey" FOREIGN KEY ("sign_language_id") REFERENCES "public"."sign_languages"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."sign_translations_history"
    ADD CONSTRAINT "sign_translations_history_sign_language_id_fkey" FOREIGN KEY ("sign_language_id") REFERENCES "public"."sign_languages"("id");



ALTER TABLE ONLY "public"."sign_translations_history"
    ADD CONSTRAINT "sign_translations_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sla_configs"
    ADD CONSTRAINT "sla_configs_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_assigned_staff_id_fkey" FOREIGN KEY ("assigned_staff_id") REFERENCES "public"."institution_staff"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_service_area_id_fkey" FOREIGN KEY ("service_area_id") REFERENCES "public"."service_areas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_traveller_id_fkey" FOREIGN KEY ("traveller_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sos_requests"
    ADD CONSTRAINT "sos_requests_traveller_profile_fkey" FOREIGN KEY ("traveller_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."traveller_sos_events"
    ADD CONSTRAINT "traveller_sos_events_sos_request_id_fkey" FOREIGN KEY ("sos_request_id") REFERENCES "public"."sos_requests"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."traveller_sos_events"
    ADD CONSTRAINT "traveller_sos_events_traveller_id_fkey" FOREIGN KEY ("traveller_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_favorite_phrases"
    ADD CONSTRAINT "user_favorite_phrases_phrase_id_fkey" FOREIGN KEY ("phrase_id") REFERENCES "public"."sign_dictionary_phrases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_favorite_phrases"
    ADD CONSTRAINT "user_favorite_phrases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_feature_guidance"
    ADD CONSTRAINT "user_feature_guidance_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."venue_sessions"
    ADD CONSTRAINT "venue_sessions_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."venue_sessions"
    ADD CONSTRAINT "venue_sessions_service_area_id_fkey" FOREIGN KEY ("service_area_id") REFERENCES "public"."service_areas"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."venue_sessions"
    ADD CONSTRAINT "venue_sessions_traveler_id_fkey" FOREIGN KEY ("traveler_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Allow all communication_dialogue_messages" ON "public"."communication_dialogue_messages" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all communication_dialogue_sessions" ON "public"."communication_dialogue_sessions" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all communication_saved_logs" ON "public"."communication_saved_logs" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all sign_asset_feedback" ON "public"."sign_asset_feedback" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all sign_translations_history" ON "public"."sign_translations_history" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all user_favorite_phrases" ON "public"."user_favorite_phrases" USING (true) WITH CHECK (true);



CREATE POLICY "Allow public access on accessibility_issue_reports" ON "public"."accessibility_issue_reports" USING (true) WITH CHECK (true);



CREATE POLICY "Allow public access on analytics_daily_metrics" ON "public"."analytics_daily_metrics" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can view active service areas" ON "public"."service_areas" FOR SELECT TO "authenticated" USING (("active" = true));



CREATE POLICY "Institution accounts can create queue events" ON "public"."queue_events" FOR INSERT TO "authenticated" WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND "public"."is_institution_account"("institution_id")));



CREATE POLICY "Institution accounts can create queue lines" ON "public"."queue_lines" FOR INSERT TO "authenticated" WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND "public"."is_institution_account"("institution_id")));



CREATE POLICY "Institution accounts can manage queue numbers" ON "public"."queue_numbers" TO "authenticated" USING ("public"."is_institution_account"("institution_id")) WITH CHECK ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts can update announcements" ON "public"."announcements" FOR UPDATE TO "authenticated" USING ("public"."is_institution_account"("institution_id")) WITH CHECK ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts can update queue lines" ON "public"."queue_lines" FOR UPDATE TO "authenticated" USING ("public"."is_institution_account"("institution_id")) WITH CHECK ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts can view queue events" ON "public"."queue_events" FOR SELECT TO "authenticated" USING ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts can view their announcements" ON "public"."announcements" FOR SELECT TO "authenticated" USING ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts can view their queue lines" ON "public"."queue_lines" FOR SELECT TO "authenticated" USING ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts manage generated_reports" ON "public"."generated_reports" TO "authenticated" USING ("public"."is_institution_account"("institution_id")) WITH CHECK ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution accounts manage sla_configs" ON "public"."sla_configs" TO "authenticated" USING ("public"."is_institution_account"("institution_id")) WITH CHECK ("public"."is_institution_account"("institution_id"));



CREATE POLICY "Institution managers can view own staff" ON "public"."institution_staff" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "institution"
  WHERE (("institution"."id" = "institution_staff"."institution_id") AND ("institution"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institution users can create own service areas" ON "public"."service_areas" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "service_areas"."institution_id") AND ("i"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institution users can delete own service areas" ON "public"."service_areas" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "service_areas"."institution_id") AND ("i"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institution users can update own profile" ON "public"."institutions" FOR UPDATE TO "authenticated" USING (("account_user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("account_user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Institution users can update own service areas" ON "public"."service_areas" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "service_areas"."institution_id") AND ("i"."account_user_id" = ( SELECT "auth"."uid"() AS "uid")))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "service_areas"."institution_id") AND ("i"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institution users can view own profile" ON "public"."institutions" FOR SELECT TO "authenticated" USING (("account_user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Institution users can view own service areas" ON "public"."service_areas" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "service_areas"."institution_id") AND ("i"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institutions can update linked SOS status" ON "public"."sos_requests" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "institution"
  WHERE (("institution"."id" = "sos_requests"."institution_id") AND ("institution"."account_user_id" = ( SELECT "auth"."uid"() AS "uid")))))) WITH CHECK ((("status" = ANY (ARRAY['acknowledged'::"text", 'resolved'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."institutions" "institution"
  WHERE (("institution"."id" = "sos_requests"."institution_id") AND ("institution"."account_user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Institutions can view linked SOS requests" ON "public"."sos_requests" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."institutions" "institution"
  WHERE (("institution"."id" = "sos_requests"."institution_id") AND ("institution"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Institutions can view linked SOS traveller profiles" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."sos_requests" "request"
     JOIN "public"."institutions" "institution" ON (("institution"."id" = "request"."institution_id")))
  WHERE (("request"."traveller_id" = "user_profiles"."id") AND ("institution"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Owners and staff update requests" ON "public"."assistance_requests" FOR UPDATE USING ((("user_id" = "auth"."uid"()) OR "public"."is_venue_staff"())) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."is_venue_staff"()));



CREATE POLICY "Public can view active announcements" ON "public"."announcements" FOR SELECT TO "authenticated", "anon" USING ((("status" = 'active'::"text") AND ("published_at" IS NOT NULL) AND ("published_at" <= "now"()) AND (("expires_at" IS NULL) OR ("expires_at" > "now"()))));



CREATE POLICY "Public can view active institutions" ON "public"."institutions" FOR SELECT TO "authenticated", "anon" USING ("active");



CREATE POLICY "Public can view open queue lines" ON "public"."queue_lines" FOR SELECT TO "authenticated", "anon" USING (("status" <> 'closed'::"text"));



CREATE POLICY "Public can view queue numbers" ON "public"."queue_numbers" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public read communication_quick_phrases" ON "public"."communication_quick_phrases" FOR SELECT USING (true);



CREATE POLICY "Public read sign_categories" ON "public"."sign_categories" FOR SELECT USING (true);



CREATE POLICY "Public read sign_dictionary_phrases" ON "public"."sign_dictionary_phrases" FOR SELECT USING (true);



CREATE POLICY "Public read sign_languages" ON "public"."sign_languages" FOR SELECT USING (true);



CREATE POLICY "Public read sign_media_assets" ON "public"."sign_media_assets" FOR SELECT USING (true);



CREATE POLICY "Request owner and staff insert messages" ON "public"."assistance_chat_messages" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."assistance_requests" "r"
  WHERE (("r"."id" = "assistance_chat_messages"."request_id") AND (("r"."user_id" = "auth"."uid"()) OR "public"."is_venue_staff"())))));



CREATE POLICY "Request owner and staff see messages" ON "public"."assistance_chat_messages" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."assistance_requests" "r"
  WHERE (("r"."id" = "assistance_chat_messages"."request_id") AND (("r"."user_id" = "auth"."uid"()) OR "public"."is_venue_staff"())))));



CREATE POLICY "Staff can view linked institution" ON "public"."institutions" FOR SELECT TO "authenticated" USING (("id" = ( SELECT "public"."current_staff_institution_id"() AS "current_staff_institution_id")));



CREATE POLICY "Staff can view own profile" ON "public"."institution_staff" FOR SELECT TO "authenticated" USING (("auth_user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Travelers create their own requests" ON "public"."assistance_requests" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Travelers see own requests, staff see all" ON "public"."assistance_requests" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_venue_staff"()));



CREATE POLICY "Traveller creates own SOS history" ON "public"."traveller_sos_events" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "traveller_id") AND (("sos_request_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."sos_requests" "r"
  WHERE (("r"."id" = "traveller_sos_events"."sos_request_id") AND ("r"."traveller_id" = ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "Traveller reads own SOS history" ON "public"."traveller_sos_events" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "traveller_id"));



CREATE POLICY "Traveller reads own institution SOS requests" ON "public"."sos_requests" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "traveller_id"));



CREATE POLICY "Traveller updates own SOS history" ON "public"."traveller_sos_events" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "traveller_id")) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "traveller_id") AND (("sos_request_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."sos_requests" "r"
  WHERE (("r"."id" = "traveller_sos_events"."sos_request_id") AND ("r"."traveller_id" = ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "Travellers can create own SOS requests" ON "public"."sos_requests" FOR INSERT TO "authenticated" WITH CHECK ((("traveller_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'sent'::"text") AND (NOT (EXISTS ( SELECT 1
   FROM "public"."institutions" "institution_account"
  WHERE ("institution_account"."account_user_id" = ( SELECT "auth"."uid"() AS "uid"))))) AND (EXISTS ( SELECT 1
   FROM "public"."service_areas" "area"
  WHERE (("area"."id" = "sos_requests"."service_area_id") AND ("area"."institution_id" = "sos_requests"."institution_id") AND ("area"."active" = true) AND ("public"."haversine_distance_m"("sos_requests"."latitude", "sos_requests"."longitude", "area"."latitude", "area"."longitude") <= ("area"."radius_m")::double precision))))));



CREATE POLICY "Travellers can view own SOS requests" ON "public"."sos_requests" FOR SELECT TO "authenticated" USING (("traveller_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Travellers can view their claimed queue notifications" ON "public"."queue_events" FOR SELECT TO "authenticated" USING ((("event_type" = 'notified'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."queue_numbers"
  WHERE (("queue_numbers"."id" = "queue_events"."queue_number_id") AND ("queue_numbers"."traveler_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Users can add their emergency contacts" ON "public"."emergency_contacts" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can create their accessibility preferences" ON "public"."accessibility_preferences" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their emergency communication card" ON "public"."emergency_communication_cards" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can create their own feature guidance" ON "public"."user_feature_guidance" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their emergency communication card" ON "public"."emergency_communication_cards" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their emergency contacts" ON "public"."emergency_contacts" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can insert own profile" ON "public"."user_profiles" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can read own profile" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can read their accessibility preferences" ON "public"."accessibility_preferences" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read their own feature guidance" ON "public"."user_feature_guidance" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own profile" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their accessibility preferences" ON "public"."accessibility_preferences" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their emergency communication card" ON "public"."emergency_communication_cards" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their emergency contacts" ON "public"."emergency_contacts" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own feature guidance" ON "public"."user_feature_guidance" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can view their emergency communication card" ON "public"."emergency_communication_cards" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their emergency contacts" ON "public"."emergency_contacts" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own profile" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Venue accounts update their own institution staff" ON "public"."institution_staff" FOR UPDATE USING ((("institution_id" = "public"."current_staff_institution_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "institution_staff"."institution_id") AND ("i"."account_user_id" = "auth"."uid"())))))) WITH CHECK ((("institution_id" = "public"."current_staff_institution_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."institutions" "i"
  WHERE (("i"."id" = "institution_staff"."institution_id") AND ("i"."account_user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."accessibility_issue_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."accessibility_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."analytics_daily_metrics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "announcement_staff_insert" ON "public"."announcements" FOR INSERT TO "authenticated" WITH CHECK ((("created_by" = "auth"."uid"()) AND "public"."can_manage_announcement_institution"("institution_id")));



CREATE POLICY "announcement_staff_update" ON "public"."announcements" FOR UPDATE TO "authenticated" USING ("public"."can_manage_announcement_institution"("institution_id")) WITH CHECK ("public"."can_manage_announcement_institution"("institution_id"));



ALTER TABLE "public"."announcements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assistance_chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assistance_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "authenticated delete" ON "public"."traveler_live_locations" FOR DELETE USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "authenticated read" ON "public"."traveler_live_locations" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



ALTER TABLE "public"."communication_dialogue_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."communication_dialogue_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."communication_quick_phrases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."communication_saved_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emergency_communication_cards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emergency_contact_verifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emergency_contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."generated_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."institution_staff" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."institutions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "institutions_account_owner_update" ON "public"."institutions" FOR UPDATE TO "authenticated" USING ((("account_user_id" = "auth"."uid"()) AND ("active" = true))) WITH CHECK ((("account_user_id" = "auth"."uid"()) AND ("active" = true)));



ALTER TABLE "public"."queue_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."queue_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."queue_numbers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "queue_numbers_claim_waiting_number" ON "public"."queue_numbers" FOR UPDATE TO "authenticated" USING (("status" = 'waiting'::"text")) WITH CHECK (("status" = 'waiting'::"text"));



ALTER TABLE "public"."service_areas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_asset_feedback" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_dictionary_phrases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_languages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_media_assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sign_translations_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sla_configs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sos_active_service_areas" ON "public"."service_areas" FOR SELECT TO "authenticated" USING (("active" = true));



CREATE POLICY "sos_history_read" ON "public"."sos_requests" FOR SELECT TO "authenticated" USING ((("traveller_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."can_manage_sos_institution"("institution_id")));



CREATE POLICY "sos_history_read_boundary" ON "public"."sos_requests" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("traveller_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."can_manage_sos_institution"("institution_id")));



CREATE POLICY "sos_owner_insert" ON "public"."sos_requests" FOR INSERT TO "authenticated" WITH CHECK ((("traveller_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'sent'::"text") AND ("assigned_staff_id" IS NULL)));



CREATE POLICY "sos_owner_insert_boundary" ON "public"."sos_requests" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK ((("traveller_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'sent'::"text") AND ("assigned_staff_id" IS NULL)));



CREATE POLICY "sos_progress_update" ON "public"."sos_requests" FOR UPDATE TO "authenticated" USING ("public"."can_manage_sos_institution"("institution_id")) WITH CHECK ("public"."can_manage_sos_institution"("institution_id"));



CREATE POLICY "sos_progress_update_boundary" ON "public"."sos_requests" AS RESTRICTIVE FOR UPDATE TO "authenticated" USING ("public"."can_manage_sos_institution"("institution_id")) WITH CHECK ("public"."can_manage_sos_institution"("institution_id"));



ALTER TABLE "public"."sos_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sos_staff_directory" ON "public"."institution_staff" FOR SELECT TO "authenticated" USING ("public"."can_manage_sos_institution"("institution_id"));



CREATE POLICY "sos_staff_directory_boundary" ON "public"."institution_staff" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("auth_user_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."can_manage_sos_institution"("institution_id")));



CREATE POLICY "staff_manager_delete_boundary" ON "public"."institution_staff" AS RESTRICTIVE FOR DELETE TO "authenticated" USING ("public"."can_manage_sos_institution"("institution_id"));



CREATE POLICY "staff_manager_insert_boundary" ON "public"."institution_staff" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK ("public"."can_manage_sos_institution"("institution_id"));



CREATE POLICY "staff_manager_update_boundary" ON "public"."institution_staff" AS RESTRICTIVE FOR UPDATE TO "authenticated" USING ("public"."can_manage_sos_institution"("institution_id")) WITH CHECK ("public"."can_manage_sos_institution"("institution_id"));



CREATE POLICY "traveler upsert own" ON "public"."traveler_live_locations" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."traveler_live_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."traveller_sos_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_favorite_phrases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_feature_guidance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "venue_session_insert_own" ON "public"."venue_sessions" FOR INSERT TO "authenticated" WITH CHECK (("traveler_id" = "auth"."uid"()));



CREATE POLICY "venue_session_read_own" ON "public"."venue_sessions" FOR SELECT TO "authenticated" USING (("traveler_id" = "auth"."uid"()));



CREATE POLICY "venue_session_update_own" ON "public"."venue_sessions" FOR UPDATE TO "authenticated" USING (("traveler_id" = "auth"."uid"())) WITH CHECK (("traveler_id" = "auth"."uid"()));



ALTER TABLE "public"."venue_sessions" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_announcement_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."apply_announcement_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_announcement_status"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_manage_announcement_institution"("p_institution_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_manage_announcement_institution"("p_institution_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_manage_announcement_institution"("p_institution_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_manage_sos_institution"("p_institution_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_manage_sos_institution"("p_institution_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_manage_sos_institution"("p_institution_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_staff_institution_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_staff_institution_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_staff_institution_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_staff_institution_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_service_area_announcements"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_service_area_announcements"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_service_area_announcements"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_service_area_dependents"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_service_area_dependents"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_service_area_dependents"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_queue_line_not_closed"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_queue_line_not_closed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_queue_line_not_closed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_service_area_assignment"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_service_area_assignment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_service_area_assignment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_sos_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_sos_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_sos_status_transition"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_sos_traveller_names"("p_request_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_sos_traveller_names"("p_request_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_sos_traveller_names"("p_request_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_traveller_sos_history"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_traveller_sos_history"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_traveller_sos_history"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_user_analytics"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_user_analytics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_analytics"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."haversine_distance_m"("latitude_a" double precision, "longitude_a" double precision, "latitude_b" double precision, "longitude_b" double precision) TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_institution_account"("p_institution_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_institution_account"("p_institution_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_institution_account"("p_institution_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_traveller_account"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_traveller_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_traveller_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_venue_staff"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_venue_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_venue_staff"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_institution_traveller_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_institution_traveller_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_institution_traveller_profile"() TO "service_role";



GRANT ALL ON TABLE "public"."queue_lines" TO "anon";
GRANT ALL ON TABLE "public"."queue_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."queue_lines" TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_call_next"("p_queue_line_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_call_next"("p_queue_line_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_call_next"("p_queue_line_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."queue_increment_number"("p_number" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."queue_increment_number"("p_number" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_increment_number"("p_number" "text") TO "service_role";



GRANT ALL ON TABLE "public"."queue_events" TO "anon";
GRANT ALL ON TABLE "public"."queue_events" TO "authenticated";
GRANT ALL ON TABLE "public"."queue_events" TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_log_event"("p_queue_line_id" "uuid", "p_number" "text", "p_event_type" "text", "p_details" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."queue_numbers" TO "anon";
GRANT ALL ON TABLE "public"."queue_numbers" TO "authenticated";
GRANT ALL ON TABLE "public"."queue_numbers" TO "service_role";



GRANT UPDATE("traveler_id") ON TABLE "public"."queue_numbers" TO "authenticated";



GRANT ALL ON FUNCTION "public"."queue_mark_number"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."queue_mark_number"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_mark_number"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_mark_number_and_call_next"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_mark_number_and_call_next"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_mark_number_and_call_next"("p_queue_line_id" "uuid", "p_number" "text", "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_notify_number"("p_queue_line_id" "uuid", "p_number" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_staff_can_manage"("p_institution_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_track_waiting_number"("p_queue_line_id" "uuid", "p_number" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_track_waiting_number"("p_queue_line_id" "uuid", "p_number" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_track_waiting_number"("p_queue_line_id" "uuid", "p_number" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_feature_usage"("p_feature_key" "text", "p_event" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_feature_usage"("p_feature_key" "text", "p_event" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_feature_usage"("p_feature_key" "text", "p_event" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_announcement_statuses"() TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_announcement_statuses"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_announcement_statuses"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_emergency_contact_verification_on_email_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_emergency_contact_verification_on_email_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_institution_staff_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_institution_staff_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_institution_staff_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_institutions_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_institutions_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_institutions_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_primary_emergency_contact"("contact_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_primary_emergency_contact"("contact_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_primary_emergency_contact"("contact_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_service_areas_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_service_areas_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_service_areas_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_assistance_staff_availability"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_assistance_staff_availability"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_assistance_staff_availability"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_institution_email_verification"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_institution_email_verification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_institution_email_verification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_sos_staff_availability"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_sos_staff_availability"() TO "service_role";



GRANT ALL ON FUNCTION "public"."travelease_handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."travelease_handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."travelease_handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_my_staff_name"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_staff_name"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_my_staff_name"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_sos_progress"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_sos_progress"() TO "service_role";



GRANT ALL ON FUNCTION "public"."withdraw_announcements_for_inactive_area"() TO "anon";
GRANT ALL ON FUNCTION "public"."withdraw_announcements_for_inactive_area"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."withdraw_announcements_for_inactive_area"() TO "service_role";



GRANT ALL ON TABLE "public"."accessibility_issue_reports" TO "anon";
GRANT ALL ON TABLE "public"."accessibility_issue_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."accessibility_issue_reports" TO "service_role";



GRANT ALL ON TABLE "public"."accessibility_preferences" TO "anon";
GRANT ALL ON TABLE "public"."accessibility_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."accessibility_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."analytics_daily_metrics" TO "anon";
GRANT ALL ON TABLE "public"."analytics_daily_metrics" TO "authenticated";
GRANT ALL ON TABLE "public"."analytics_daily_metrics" TO "service_role";



GRANT ALL ON TABLE "public"."announcements" TO "anon";
GRANT ALL ON TABLE "public"."announcements" TO "authenticated";
GRANT ALL ON TABLE "public"."announcements" TO "service_role";



GRANT ALL ON TABLE "public"."assistance_chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."assistance_chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."assistance_chat_messages" TO "service_role";



GRANT ALL ON TABLE "public"."assistance_requests" TO "anon";
GRANT ALL ON TABLE "public"."assistance_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."assistance_requests" TO "service_role";



GRANT ALL ON TABLE "public"."communication_dialogue_messages" TO "anon";
GRANT ALL ON TABLE "public"."communication_dialogue_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."communication_dialogue_messages" TO "service_role";



GRANT ALL ON TABLE "public"."communication_dialogue_sessions" TO "anon";
GRANT ALL ON TABLE "public"."communication_dialogue_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."communication_dialogue_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."communication_quick_phrases" TO "anon";
GRANT ALL ON TABLE "public"."communication_quick_phrases" TO "authenticated";
GRANT ALL ON TABLE "public"."communication_quick_phrases" TO "service_role";



GRANT ALL ON TABLE "public"."communication_saved_logs" TO "anon";
GRANT ALL ON TABLE "public"."communication_saved_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."communication_saved_logs" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_communication_cards" TO "anon";
GRANT ALL ON TABLE "public"."emergency_communication_cards" TO "authenticated";
GRANT ALL ON TABLE "public"."emergency_communication_cards" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_contact_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_contacts" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."emergency_contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."emergency_contacts" TO "service_role";



GRANT INSERT("user_id") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT INSERT("name"),UPDATE("name") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT INSERT("relationship"),UPDATE("relationship") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT INSERT("phone_number"),UPDATE("phone_number") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT INSERT("email"),UPDATE("email") ON TABLE "public"."emergency_contacts" TO "authenticated";



GRANT ALL ON TABLE "public"."generated_reports" TO "anon";
GRANT ALL ON TABLE "public"."generated_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."generated_reports" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."institution_staff" TO "authenticated";
GRANT ALL ON TABLE "public"."institution_staff" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."institutions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."institutions" TO "authenticated";
GRANT ALL ON TABLE "public"."institutions" TO "service_role";



GRANT UPDATE("name") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("branch") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("latitude") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("longitude") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("location_match_radius_m") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("institution_type") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("official_contact") ON TABLE "public"."institutions" TO "authenticated";



GRANT UPDATE("service_address") ON TABLE "public"."institutions" TO "authenticated";



GRANT ALL ON TABLE "public"."service_areas" TO "authenticated";
GRANT ALL ON TABLE "public"."service_areas" TO "service_role";



GRANT ALL ON TABLE "public"."sign_asset_feedback" TO "anon";
GRANT ALL ON TABLE "public"."sign_asset_feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_asset_feedback" TO "service_role";



GRANT ALL ON TABLE "public"."sign_categories" TO "anon";
GRANT ALL ON TABLE "public"."sign_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_categories" TO "service_role";



GRANT ALL ON TABLE "public"."sign_dictionary_phrases" TO "anon";
GRANT ALL ON TABLE "public"."sign_dictionary_phrases" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_dictionary_phrases" TO "service_role";



GRANT ALL ON TABLE "public"."sign_languages" TO "anon";
GRANT ALL ON TABLE "public"."sign_languages" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_languages" TO "service_role";



GRANT ALL ON TABLE "public"."sign_media_assets" TO "anon";
GRANT ALL ON TABLE "public"."sign_media_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_media_assets" TO "service_role";



GRANT ALL ON TABLE "public"."sign_translations_history" TO "anon";
GRANT ALL ON TABLE "public"."sign_translations_history" TO "authenticated";
GRANT ALL ON TABLE "public"."sign_translations_history" TO "service_role";



GRANT ALL ON TABLE "public"."sla_configs" TO "anon";
GRANT ALL ON TABLE "public"."sla_configs" TO "authenticated";
GRANT ALL ON TABLE "public"."sla_configs" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."sos_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."sos_requests" TO "service_role";



GRANT UPDATE("status") ON TABLE "public"."sos_requests" TO "authenticated";



GRANT UPDATE("assigned_staff_id") ON TABLE "public"."sos_requests" TO "authenticated";



GRANT ALL ON TABLE "public"."traveler_live_locations" TO "anon";
GRANT ALL ON TABLE "public"."traveler_live_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."traveler_live_locations" TO "service_role";



GRANT ALL ON TABLE "public"."traveller_sos_events" TO "authenticated";
GRANT ALL ON TABLE "public"."traveller_sos_events" TO "service_role";



GRANT ALL ON TABLE "public"."user_favorite_phrases" TO "anon";
GRANT ALL ON TABLE "public"."user_favorite_phrases" TO "authenticated";
GRANT ALL ON TABLE "public"."user_favorite_phrases" TO "service_role";



GRANT ALL ON TABLE "public"."user_feature_guidance" TO "anon";
GRANT ALL ON TABLE "public"."user_feature_guidance" TO "authenticated";
GRANT ALL ON TABLE "public"."user_feature_guidance" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."venue_sessions" TO "anon";
GRANT ALL ON TABLE "public"."venue_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."venue_sessions" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";








-- ==============================================================================
-- AUTH TRIGGERS (Auto Profile Creation & Institution Verification)
-- ==============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'travelease_on_auth_user_created'
  ) THEN
    CREATE TRIGGER travelease_on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.travelease_handle_new_user();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'sync_institution_email_verification_trigger'
  ) THEN
    CREATE TRIGGER sync_institution_email_verification_trigger
      AFTER UPDATE OF email_confirmed_at ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.sync_institution_email_verification();
  END IF;
END $$;

-- ==============================================================================
-- STORAGE BUCKETS & STORAGE POLICIES
-- ==============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'storage') THEN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES 
      ('profile-images', 'profile-images', true, 5242880, ARRAY['image/jpeg', 'image/png']::text[]),
      ('institution-registration-documents', 'institution-registration-documents', false, 10485760, ARRAY['application/pdf', 'image/jpeg', 'image/png']::text[]),
      ('chat-media', 'chat-media', true, 52428800, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm']::text[]),
      ('docs-assets', 'docs-assets', true, null, null),
      ('accessibility-reports', 'accessibility-reports', true, null, null)
    ON CONFLICT (id) DO UPDATE SET
      public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- Storage RLS Policies
    DROP POLICY IF EXISTS "Institution users can view own registration document" ON storage.objects;
    CREATE POLICY "Institution users can view own registration document" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'institution-registration-documents' AND (storage.foldername(name))[1] = (auth.uid())::text);

    DROP POLICY IF EXISTS "Public Access docs-assets" ON storage.objects;
    CREATE POLICY "Public Access docs-assets" ON storage.objects
      FOR SELECT TO public
      USING (bucket_id = 'docs-assets');

    DROP POLICY IF EXISTS "Public Insert docs-assets" ON storage.objects;
    CREATE POLICY "Public Insert docs-assets" ON storage.objects
      FOR INSERT TO public
      WITH CHECK (bucket_id = 'docs-assets');

    DROP POLICY IF EXISTS "Users can delete their profile image" ON storage.objects;
    CREATE POLICY "Users can delete their profile image" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'profile-images' AND owner_id = (auth.uid())::text);

    DROP POLICY IF EXISTS "Users can select their profile image" ON storage.objects;
    CREATE POLICY "Users can select their profile image" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'profile-images' AND (storage.foldername(name))[1] = (auth.uid())::text);

    DROP POLICY IF EXISTS "Users can update their profile image" ON storage.objects;
    CREATE POLICY "Users can update their profile image" ON storage.objects
      FOR UPDATE TO authenticated
      USING (bucket_id = 'profile-images' AND owner_id = (auth.uid())::text)
      WITH CHECK (bucket_id = 'profile-images' AND (storage.foldername(name))[1] = (auth.uid())::text);

    DROP POLICY IF EXISTS "Users can upload their profile image" ON storage.objects;
    CREATE POLICY "Users can upload their profile image" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'profile-images' AND (storage.foldername(name))[1] = (auth.uid())::text);

    DROP POLICY IF EXISTS "accessibility_reports_anon_insert" ON storage.objects;
    CREATE POLICY "accessibility_reports_anon_insert" ON storage.objects
      FOR INSERT TO anon
      WITH CHECK (bucket_id = 'accessibility-reports');

    DROP POLICY IF EXISTS "accessibility_reports_insert" ON storage.objects;
    CREATE POLICY "accessibility_reports_insert" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'accessibility-reports');

    DROP POLICY IF EXISTS "accessibility_reports_select" ON storage.objects;
    CREATE POLICY "accessibility_reports_select" ON storage.objects
      FOR SELECT TO public
      USING (bucket_id = 'accessibility-reports');

    DROP POLICY IF EXISTS "chat_media_delete" ON storage.objects;
    CREATE POLICY "chat_media_delete" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'chat-media' AND auth.uid() = owner);

    DROP POLICY IF EXISTS "chat_media_insert" ON storage.objects;
    CREATE POLICY "chat_media_insert" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'chat-media');

    DROP POLICY IF EXISTS "chat_media_select" ON storage.objects;
    CREATE POLICY "chat_media_select" ON storage.objects
      FOR SELECT TO public
      USING (bucket_id = 'chat-media');
  END IF;
END $$;
