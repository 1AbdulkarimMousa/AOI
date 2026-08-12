-- The event trigger invokes this function internally; API roles never need it.
-- Some fresh installations do not provision the optional helper.
do $migration$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$migration$;
