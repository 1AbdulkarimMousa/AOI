-- Restrict operation RPCs to authenticated workspace members.
revoke execute on function public.rpc_aoi_operations_snapshot() from anon;
revoke execute on function public.rpc_aoi_upsert_candidate(jsonb) from anon;
revoke execute on function public.rpc_aoi_log_outreach(uuid, text, text, text, text) from anon;
revoke execute on function public.rpc_aoi_add_evidence(uuid, text, text, integer, text, text, text) from anon;
revoke execute on function public.rpc_aoi_queue_email(uuid, text, text, text, timestamptz, uuid) from anon;
grant execute on function public.rpc_aoi_operations_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_outreach(uuid, text, text, text, text) to authenticated;
grant execute on function public.rpc_aoi_add_evidence(uuid, text, text, integer, text, text, text) to authenticated;
grant execute on function public.rpc_aoi_queue_email(uuid, text, text, text, timestamptz, uuid) to authenticated;
