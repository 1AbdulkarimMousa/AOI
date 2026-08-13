-- Review and checkpoint activity has dedicated history branches in the
-- briefing RPC. Exclude legacy activity_events copies to avoid duplicates.
do $$
declare
  v_definition text;
  v_old text := 'where event.project_id = v_project_id and v_role = ''admin''';
  v_new text := 'where event.project_id = v_project_id and event.event_type not in (''task_review'', ''task_checkpoint'')'
    || E'\n        and v_role = ''admin''';
begin
  select pg_get_functiondef('public.rpc_aoi_today_briefing(uuid)'::regprocedure)
  into v_definition;

  if position(v_new in v_definition) > 0 then
    return;
  end if;

  if position(v_old in v_definition) = 0 then
    raise exception 'Could not locate Today Briefing activity branch';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;
