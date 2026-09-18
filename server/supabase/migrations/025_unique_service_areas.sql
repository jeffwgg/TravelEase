-- One copy of each service area per institution, including inactive areas.
-- Existing duplicates must be reviewed and merged before this migration runs.
-- Do not delete them automatically: queues and SOS history may reference them.
begin;

create unique index if not exists service_areas_institution_name_unique
  on public.service_areas (
    institution_id,
    lower(trim(regexp_replace(name, '[[:space:]]+', ' ', 'g')))
  );

-- Six decimal places matches the location precision presented by the app.
create unique index if not exists service_areas_institution_coverage_unique
  on public.service_areas (
    institution_id,
    (round(latitude::numeric, 6)),
    (round(longitude::numeric, 6)),
    radius_m
  );

commit;
