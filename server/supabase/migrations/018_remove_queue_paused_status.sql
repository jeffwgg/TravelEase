-- Paused is not part of the queue workflow. Preserve existing lines by
-- returning them to Active before narrowing the allowed status values.
update public.queue_lines set status = 'active' where status = 'paused';

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.queue_lines'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.queue_lines drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.queue_lines
  add constraint queue_lines_status_check
  check (status in ('active', 'closed', 'reset'));
