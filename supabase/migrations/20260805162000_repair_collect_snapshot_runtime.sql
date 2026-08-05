-- PL/pgSQL defers relation-column checks until execution. Align the deployed
-- Collect snapshot with evidence_records.title without duplicating the function.
do $repair$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.rpc_aoi_collect_snapshot()'::regprocedure)
  into v_definition;
  if position('evidence.evidence_title' in v_definition) > 0 then
    execute replace(v_definition, 'evidence.evidence_title', 'evidence.title');
  end if;
end;
$repair$;
