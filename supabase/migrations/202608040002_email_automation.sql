-- Provider-neutral email automation queue.
-- A dispatcher may later connect this queue to Resend, Postmark, SES, or another approved provider.

create table if not exists public.email_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  audience text not null,
  subject text not null,
  body text not null,
  status text not null default 'draft' check (status in ('draft','approved','archived')),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.email_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  template_id uuid references public.email_templates(id) on delete set null,
  recipient text not null,
  subject text not null,
  body text not null,
  status text not null default 'queued' check (status in ('queued','sending','sent','delivered','bounced','failed','cancelled')),
  scheduled_for timestamptz not null default now(),
  provider_message_id text,
  failure_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists email_deliveries_queue_idx on public.email_deliveries (status, scheduled_for);

create table if not exists public.contact_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  email_opt_out boolean not null default false,
  reason text,
  recorded_at timestamptz not null default now(),
  unique (candidate_id)
);

alter table public.email_templates enable row level security;
alter table public.email_deliveries enable row level security;
alter table public.contact_preferences enable row level security;

drop policy if exists email_templates_admin_read on public.email_templates;
create policy email_templates_admin_read on public.email_templates for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists email_templates_admin_write on public.email_templates;
create policy email_templates_admin_write on public.email_templates for all to authenticated using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));
drop policy if exists email_deliveries_member_read on public.email_deliveries;
create policy email_deliveries_member_read on public.email_deliveries for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists contact_preferences_member_read on public.contact_preferences;
create policy contact_preferences_member_read on public.contact_preferences for select to authenticated using (public.is_org_member(organization_id));

create or replace function public.rpc_aoi_queue_email(candidate_id uuid, recipient text, email_subject text, email_body text, send_at timestamptz default now(), template_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare org_id uuid; project_id uuid; delivery public.email_deliveries%rowtype;
begin
  select membership.organization_id into org_id from public.organization_memberships membership where membership.user_id=auth.uid() and membership.status='active' limit 1;
  select c.project_id into project_id from public.candidates c where c.id=candidate_id and c.organization_id=org_id;
  if project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if exists (select 1 from public.contact_preferences preference where preference.candidate_id=candidate_id and preference.email_opt_out) then raise exception 'EMAIL_OPTED_OUT'; end if;
  if not public.is_org_admin(org_id) then raise exception 'ADMIN_APPROVAL_REQUIRED'; end if;
  insert into public.email_deliveries (organization_id, project_id, candidate_id, template_id, recipient, subject, body, scheduled_for, created_by) values (org_id, project_id, candidate_id, template_id, trim(recipient), trim(email_subject), email_body, send_at, auth.uid()) returning * into delivery;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata) values (org_id, auth.uid(), 'email_delivery', delivery.id, 'queued', jsonb_build_object('candidate_id', candidate_id, 'scheduled_for', send_at));
  return jsonb_build_object('id', delivery.id, 'status', delivery.status, 'scheduledFor', delivery.scheduled_for);
end; $$;

revoke all on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) from public;
grant execute on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) to authenticated;
