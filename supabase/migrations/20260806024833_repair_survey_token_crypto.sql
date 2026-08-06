-- pgcrypto is installed in Supabase's controlled extensions schema. The survey
-- functions otherwise use fully-qualified relations and may safely restrict
-- resolution to pg_catalog + extensions while retaining token hashing.

alter function public.rpc_aoi_submit_survey_version(uuid,integer)
  set search_path = pg_catalog, extensions;
alter function public.rpc_aoi_create_survey_link(uuid,text,text,text,jsonb)
  set search_path = pg_catalog, extensions;
alter function public.rpc_aoi_public_survey_load(text)
  set search_path = pg_catalog, extensions;
alter function public.rpc_aoi_public_survey_start(text,text,jsonb)
  set search_path = pg_catalog, extensions;
alter function public.rpc_aoi_public_survey_save(text,uuid,text,jsonb)
  set search_path = pg_catalog, extensions;
alter function public.rpc_aoi_public_survey_submit(text,uuid,text,jsonb,text,jsonb,jsonb)
  set search_path = pg_catalog, extensions;
