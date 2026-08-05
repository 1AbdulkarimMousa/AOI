-- The Collect snapshot must not reopen hardened direct CRM access. Resolve
-- external identities through visible respondents and recruitment RLS only.
drop policy if exists contact_external_identities_read on public.contact_external_identities;
create policy contact_external_identities_read on public.contact_external_identities
  for select to authenticated using (
    public.is_org_admin(organization_id)
    or exists (
      select 1 from public.respondents respondent
      where respondent.crm_contact_id = contact_external_identities.crm_contact_id
        and respondent.organization_id = contact_external_identities.organization_id
        and respondent.project_id = contact_external_identities.project_id
        and (respondent.assigned_to = (select auth.uid()) or respondent.workflow_status = 'approved')
    )
  );

grant select on public.participant_recruitment to authenticated;
