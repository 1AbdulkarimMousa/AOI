-- Cache auth.uid() once per statement in survey policies to avoid per-row calls.

drop policy if exists survey_drafts_assignee_read on public.survey_drafts;
create policy survey_drafts_assignee_read on public.survey_drafts for select to authenticated
  using (exists (select 1 from public.survey_assets asset where asset.id=asset_id and asset.organization_id=organization_id
    and (public.is_org_admin(organization_id) or asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));

drop policy if exists survey_invitations_assignee_read on public.survey_invitations;
create policy survey_invitations_assignee_read on public.survey_invitations for select to authenticated
  using (public.is_org_admin(organization_id) or exists (select 1 from public.survey_links link join public.survey_assets asset on asset.id=link.asset_id where link.id=link_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));

drop policy if exists survey_submissions_assignee_read on public.survey_submissions;
create policy survey_submissions_assignee_read on public.survey_submissions for select to authenticated
  using (public.is_org_admin(organization_id) or assigned_to=(select auth.uid()) or exists (select 1 from public.survey_assets asset where asset.id=asset_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));

drop policy if exists survey_answers_submission_read on public.survey_answers;
create policy survey_answers_submission_read on public.survey_answers for select to authenticated
  using (exists (select 1 from public.survey_submissions submission where submission.id=submission_id
    and (public.is_org_admin(organization_id) or submission.assigned_to=(select auth.uid()) or exists (select 1 from public.survey_assets asset where asset.id=submission.asset_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))))));

drop policy if exists survey_reviews_assignee_read on public.survey_reviews;
create policy survey_reviews_assignee_read on public.survey_reviews for select to authenticated
  using (public.is_org_admin(organization_id) or reviewer_id=(select auth.uid()));

drop policy if exists survey_transfer_creator_read on public.survey_transfer_jobs;
create policy survey_transfer_creator_read on public.survey_transfer_jobs for select to authenticated
  using (public.is_org_admin(organization_id) or created_by=(select auth.uid()));
