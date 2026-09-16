-- Queue service starts as soon as staff calls a number. The application no
-- longer has a separate `serving` state, so preserve any existing active
-- records by treating them as called.
update public.queue_numbers
set status = 'called'
where status = 'serving';
