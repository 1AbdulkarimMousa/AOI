-- Enforce safe external navigation at the database boundary. NOT VALID keeps
-- legacy rows deployable while every new or changed row is checked.

alter table public.evidence_records drop constraint if exists evidence_records_source_link_http;
alter table public.evidence_records add constraint evidence_records_source_link_http
  check (source_link is null or source_link ~* '^https?://') not valid;

alter table public.pmf_observations drop constraint if exists pmf_observations_source_link_http;
alter table public.pmf_observations add constraint pmf_observations_source_link_http
  check (source_link is null or source_link ~* '^https?://') not valid;

alter table public.crm_contacts drop constraint if exists crm_contacts_source_url_http;
alter table public.crm_contacts add constraint crm_contacts_source_url_http
  check (source_url is null or source_url ~* '^https?://') not valid;

alter table public.candidates drop constraint if exists candidates_source_url_http;
alter table public.candidates add constraint candidates_source_url_http
  check (source_url is null or source_url ~* '^https?://') not valid;
