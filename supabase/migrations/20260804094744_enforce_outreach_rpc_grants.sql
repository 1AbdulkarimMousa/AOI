-- Explicitly remove the default anonymous EXECUTE grants on operation RPCs.
revoke all privileges on function public.rpc_aoi_operations_snapshot() from anon;
revoke all privileges on function public.rpc_aoi_upsert_candidate(jsonb) from anon;
revoke all privileges on function public.rpc_aoi_log_outreach(uuid, text, text, text, text) from anon;
revoke all privileges on function public.rpc_aoi_add_evidence(uuid, text, text, integer, text, text, text) from anon;
revoke all privileges on function public.rpc_aoi_queue_email(uuid, text, text, text, timestamptz, uuid) from anon;
