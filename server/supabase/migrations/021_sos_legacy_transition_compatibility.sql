-- Apply after 020. Extend the legacy validator that emits the reported error.
-- Preserve its ownership checks, timestamps, permissions and trigger bindings.
begin;
do $$
declare
  validator record;
  original text;
  repaired text;
begin
  if to_regprocedure('public.validate_sos_progress()') is null then
    raise exception 'Apply migration 020 before 021';
  end if;
  for validator in
    select distinct p.oid from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.sos_requests'::regclass and not t.tgisinternal
      and p.prosrc ilike '%Invalid SOS status transition%'
  loop
    original := pg_get_functiondef(validator.oid);
    -- Only modify the old acknowledged -> resolved predicate. Matching is
    -- case/whitespace insensitive; unfamiliar validators fail for inspection.
    repaired := regexp_replace(original,
      $pattern$old\.status\s*=\s*'acknowledged'\s+and\s+new\.status\s*=\s*'resolved'$pattern$,
      $replacement$((old.status = 'acknowledged' and new.status in ('assigned', 'resolved'))
        or (old.status = 'assigned' and new.status in ('en_route', 'resolved'))
        or (old.status = 'en_route' and new.status = 'resolved'))$replacement$, 'gi');
    if repaired = original and original not ilike '%new.status in (''assigned'', ''resolved'')%' then
      raise exception 'Legacy SOS validator % has an unfamiliar transition expression. Inspect pg_get_functiondef(%) before updating it.', validator.oid::regprocedure, validator.oid;
    end if;
    if repaired <> original then execute repaired; end if;
  end loop;
end $$;
notify pgrst, 'reload schema';
commit;
