-- Task reviews are projected from task_review_history. Checkpoints have no
-- separate history source, so retain their activity_events rows.
do $$
declare
  v_definition text;
  v_old text := 'event.event_type not in (''task_review'', ''task_checkpoint'')';
  v_new text := 'event.event_type not in (''task_review'')';
begin
  select pg_get_functiondef('public.rpc_aoi_today_briefing(uuid)'::regprocedure)
  into v_definition;

  if position(v_new in v_definition) > 0 then
    return;
  end if;

  if position(v_old in v_definition) = 0 then
    raise exception 'Could not locate Today Briefing activity filter';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;
