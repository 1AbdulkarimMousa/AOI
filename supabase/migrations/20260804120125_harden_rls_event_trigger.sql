-- The event trigger invokes this function internally; API roles never need it.
revoke all on function public.rls_auto_enable() from public, anon, authenticated;
