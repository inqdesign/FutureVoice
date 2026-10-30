-- admin_raw() reads the whole console in one call and now takes ~8 s, which is
-- exactly the API roles' statement_timeout (8 s): the console failed with 57014
-- about half the time. PostgREST applies a function's own statement_timeout to
-- the RPC call, so the console gets a longer leash without touching any role.
alter function public.admin_raw() set statement_timeout = '30s';
