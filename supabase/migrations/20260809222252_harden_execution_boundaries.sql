-- Keep bootstrap context available for password changes while ensuring every
-- content RPC resolves one deterministic, active organization/project pair.
create or replace function public.is_org_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile
      on profile.id = membership.user_id
     and profile.status = 'active'
     and not profile.must_change_password
    join public.organizations organization
      on organization.id = membership.organization_id
     and organization.status = 'active'
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  );
$$;

create or replace function public.is_org_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile
      on profile.id = membership.user_id
     and profile.status = 'active'
     and not profile.must_change_password
    join public.organizations organization
      on organization.id = membership.organization_id
     and organization.status = 'active'
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.role = 'admin'
      and membership.status = 'active'
  );
$$;

revoke all on function public.is_org_member(uuid), public.is_org_admin(uuid) from public, anon;
grant execute on function public.is_org_member(uuid), public.is_org_admin(uuid) to authenticated;

create or replace function public.rpc_current_user_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'loginIdentifier', profile.login_identifier,
    'locale', profile.locale,
    'mustChangePassword', profile.must_change_password,
    'passwordReminderSeededAt', profile.password_reminder_seeded_at,
    'passwordChangedAt', profile.password_changed_at,
    'passwordReminderSnoozedUntil', profile.password_reminder_snoozed_until,
    'jobTitle', profile.job_title,
    'bio', profile.bio,
    'phone', profile.phone,
    'timezone', profile.timezone,
    'avatarKey', profile.avatar_key,
    'avatarPath', profile.avatar_path,
    'emailConfirmed', true,
    'role', membership.role,
    'isOwner', membership.is_owner,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles profile
  join public.organization_memberships membership
    on membership.user_id = profile.id
   and membership.status in ('active', 'password_change_required')
  join public.organizations organization
    on organization.id = membership.organization_id
   and organization.status = 'active'
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id
      and project_row.status = 'active'
    order by project_row.created_at, project_row.id
    limit 1
  ) project on true
  join auth.users auth_user
    on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
  where profile.id = auth.uid()
    and profile.status in ('active', 'password_change_required')
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
$$;

revoke all on function public.rpc_current_user_context() from public, anon;
grant execute on function public.rpc_current_user_context() to authenticated;

create or replace function public.rpc_aoi_demo_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_organization_id uuid;
  current_project_id uuid;
  membership_role text;
  result jsonb;
begin
  select membership.organization_id, membership.role
  into current_organization_id, membership_role
  from public.organization_memberships membership
  join public.profiles profile
    on profile.id = membership.user_id
   and profile.status = 'active'
   and not profile.must_change_password
  join public.organizations organization
    on organization.id = membership.organization_id
   and organization.status = 'active'
  join auth.users auth_user
    on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  if current_organization_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id into current_project_id
  from public.projects project
  where project.organization_id = current_organization_id and project.status = 'active'
  order by project.created_at, project.id
  limit 1;
  if current_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  select jsonb_build_object(
    'organization', jsonb_build_object('id', organization.id, 'name', organization.name, 'slug', organization.slug),
    'project', jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name, 'description', project.description, 'currentWeek', project.current_week, 'startDate', project.start_date, 'endDate', project.end_date),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', metric.metric_key, 'label', metric.label, 'value', metric.value, 'target', metric.target, 'unit', metric.unit, 'delta', metric.delta) order by case metric.metric_key when 'weekly_plan' then 1 when 'evidence_records' then 2 when 'pending_reviews' then 3 when 'active_blockers' then 4 else 99 end) from public.project_metrics metric where metric.project_id = project.id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', task.id, 'title', task.title, 'objective', task.objective, 'status', task.status, 'priority', task.priority, 'ownerName', task.owner_name, 'ownerInitials', task.owner_initials, 'dueDate', task.due_date, 'pmfLayer', task.pmf_layer, 'progress', task.progress, 'points', task.points) order by task.due_date nulls last, task.priority desc) from public.tasks task where task.project_id = project.id and (membership_role = 'admin' or task.assigned_to = auth.uid())), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object('id', sample.id, 'label', sample.label, 'pmfLayer', sample.pmf_layer, 'actual', sample.actual, 'target', sample.target, 'accent', sample.accent) order by case sample.label when 'Dental professionals' then 1 when 'Consumer interviews' then 2 when 'Concept-test responses' then 3 when 'Product test users' then 4 else 99 end) from public.sample_plan_items sample where sample.project_id = project.id), '[]'::jsonb),
    'pmfLayers', coalesce((select jsonb_agg(jsonb_build_object('id', layer.id, 'code', layer.code, 'name', layer.name, 'sequence', layer.sequence, 'confidence', layer.confidence, 'status', layer.status, 'evidenceCount', layer.evidence_count, 'counterevidenceCount', layer.counterevidence_count, 'nextAction', layer.next_action) order by layer.sequence) from public.pmf_layers layer where layer.project_id = project.id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('id', activity.id, 'actorName', activity.actor_name, 'actorInitials', activity.actor_initials, 'action', activity.action, 'subject', activity.subject, 'eventType', activity.event_type, 'occurredAt', activity.occurred_at) order by activity.occurred_at desc) from public.activity_events activity where activity.project_id = project.id), '[]'::jsonb),
    'signals', coalesce((select jsonb_agg(jsonb_build_object('id', signal.id, 'theme', signal.theme, 'stance', signal.stance, 'evidenceCount', signal.evidence_count, 'changePercent', signal.change_percent, 'strength', signal.strength) order by signal.evidence_count desc) from public.research_signals signal where signal.project_id = project.id), '[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id', progress.id, 'displayName', progress.display_name, 'initials', progress.initials, 'roleLabel', progress.role_label, 'points', progress.points, 'weeklyPoints', progress.weekly_points, 'streakDays', progress.streak_days, 'completedTasks', progress.completed_tasks, 'rank', progress.rank) order by progress.rank) from public.team_progress progress where progress.project_id = project.id), '[]'::jsonb),
    'generatedAt', now()
  ) into result
  from public.projects project
  join public.organizations organization on organization.id = project.organization_id
  where project.id = current_project_id and project.organization_id = current_organization_id;
  return result;
end;
$$;

revoke all on function public.rpc_aoi_demo_dashboard() from public, anon;
grant execute on function public.rpc_aoi_demo_dashboard() to authenticated;

-- Raw PMF payloads use the respondent's current consent state. Unlinked aggregate
-- evidence remains available, and tenant/project predicates stay explicit.
create or replace function public.rpc_aoi_pmf_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile
    on profile.id = membership.user_id and profile.status = 'active' and not profile.must_change_password
  where membership.user_id = auth.uid()
    and membership.status = 'active'
    and public.is_org_member(membership.organization_id)
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id
  limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'segments', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name,'audienceType',s.audience_type) order by s.sequence) from public.research_segments s where s.organization_id=v_org_id and s.project_id=v_project_id and s.active),'[]'::jsonb),
    'respondents', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'externalId',r.external_id,'segmentCode',s.code,'segmentName',s.name,'respondentType',r.respondent_type,'specialtyStatus',r.specialty_status,'recruitmentSource',r.recruitment_source,'consentStatus',r.consent_status,'status',r.status,'workflowStatus',r.workflow_status,'assignedTo',r.assigned_to,'createdAt',r.created_at) order by r.created_at desc) from public.respondents r join public.research_segments s on s.id=r.segment_id where r.organization_id=v_org_id and r.project_id=v_project_id),'[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'respondentId',x.respondent_id,'segmentCode',s.code,'pmfLayer',x.pmf_layer,'method',x.method,'sessionDate',x.session_date,'unmetNeed',x.unmet_need,'workflowStatus',x.workflow_status,'createdAt',x.created_at) order by x.session_date desc) from public.research_sessions x join public.research_segments s on s.id=x.segment_id where x.organization_id=v_org_id and x.project_id=v_project_id),'[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'respondentId',e.respondent_id,'sessionId',e.session_id,'segmentCode',s.code,'pmfLayer',e.pmf_layer,'dimension',e.dimension,'title',e.title,'evidenceText',e.evidence_text,'stance',e.stance,'strength',e.strength,'sourceLink',e.source_link,'limitations',e.limitations,'consentStatus',e.consent_status,'workflowStatus',e.workflow_status,'createdAt',e.created_at) order by e.created_at desc) from public.evidence_records e left join public.research_segments s on s.id=e.segment_id where e.organization_id=v_org_id and e.project_id=v_project_id and (e.respondent_id is null or exists (select 1 from public.respondents respondent where respondent.id=e.respondent_id and respondent.organization_id=e.organization_id and respondent.project_id=e.project_id and respondent.consent_status = 'granted'))),'[]'::jsonb),
    'productEvents', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'respondentId',e.respondent_id,'segmentCode',s.code,'eventDate',e.event_date,'studyWeek',e.study_week,'triggerType',e.trigger_type,'captureSuccess',e.capture_success,'validImage',e.valid_image,'compareUsed',e.compare_used,'resultUnderstood',e.result_understood,'valueObtained',e.value_obtained,'actionTaken',e.action_taken,'sharedWithDoctor',e.shared_with_doctor,'mainFriction',e.main_friction,'workflowStatus',e.workflow_status,'createdAt',e.created_at) order by e.event_date desc) from public.product_events e join public.research_segments s on s.id=e.segment_id where e.organization_id=v_org_id and e.project_id=v_project_id),'[]'::jsonb),
    'valueExchange', coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'respondentId',v.respondent_id,'segmentCode',s.code,'observedAt',v.observed_at,'hardwarePrice',v.hardware_price,'reasonablePriceMin',v.reasonable_price_min,'reasonablePriceMax',v.reasonable_price_max,'purchaseIntent',v.purchase_intent,'preferredOffer',v.preferred_offer,'subscriptionPlan',v.subscription_plan,'commitmentType',v.commitment_type,'commitmentAmount',v.commitment_amount,'mainObjection',v.main_objection,'postTrialPurchaseIntent',v.post_trial_purchase_intent,'workflowStatus',v.workflow_status,'createdAt',v.created_at) order by v.observed_at desc) from public.value_exchange_observations v join public.research_segments s on s.id=v.segment_id where v.organization_id=v_org_id and v.project_id=v_project_id),'[]'::jsonb),
    'definitions', coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'code',d.code,'layer',d.pmf_layer,'dimension',d.dimension,'label',d.label,'valueType',d.value_type,'unit',d.unit) order by d.pmf_layer,d.sequence) from public.pmf_metric_definitions d where d.organization_id=v_org_id and d.project_id=v_project_id and d.active),'[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'definitionId',o.definition_id,'respondentId',o.respondent_id,'segmentCode',s.code,'numericValue',o.numeric_value,'booleanValue',o.boolean_value,'textValue',o.text_value,'sourceLink',o.source_link,'workflowStatus',o.workflow_status,'createdAt',o.created_at) order by o.created_at desc) from public.pmf_observations o join public.research_segments s on s.id=o.segment_id where o.organization_id=v_org_id and o.project_id=v_project_id and (o.respondent_id is null or exists (select 1 from public.respondents respondent where respondent.id=o.respondent_id and respondent.organization_id=o.organization_id and respondent.project_id=o.project_id and respondent.consent_status = 'granted'))),'[]'::jsonb),
    'hypotheses', coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'code',h.code,'pmfLayer',h.pmf_layer,'statement',h.statement,'successCriteria',h.success_criteria,'decisionStatus',h.decision_status) order by h.code) from public.hypotheses h where h.organization_id=v_org_id and h.project_id=v_project_id),'[]'::jsonb),
    'reviewQueue', coalesce((select jsonb_agg(q order by q->>'submittedAt') from (
      select jsonb_build_object('id',r.id,'recordType','respondent','title',r.external_id,'workflowStatus',r.workflow_status,'submittedAt',r.submitted_at,'updatedAt',r.updated_at) q from public.respondents r where r.organization_id=v_org_id and r.project_id=v_project_id and r.workflow_status='submitted'
      union all select jsonb_build_object('id',s.id,'recordType','session','title',s.method,'workflowStatus',s.workflow_status,'submittedAt',s.submitted_at,'updatedAt',s.updated_at) from public.research_sessions s where s.organization_id=v_org_id and s.project_id=v_project_id and s.workflow_status='submitted'
      union all select jsonb_build_object('id',e.id,'recordType','evidence','title',e.title,'workflowStatus',e.workflow_status,'submittedAt',e.submitted_at,'updatedAt',e.updated_at) from public.evidence_records e where e.organization_id=v_org_id and e.project_id=v_project_id and e.workflow_status='submitted'
      union all select jsonb_build_object('id',p.id,'recordType','product_event','title','Product event','workflowStatus',p.workflow_status,'submittedAt',p.submitted_at,'updatedAt',p.updated_at) from public.product_events p where p.organization_id=v_org_id and p.project_id=v_project_id and p.workflow_status='submitted'
      union all select jsonb_build_object('id',v.id,'recordType','value_exchange','title','Value exchange','workflowStatus',v.workflow_status,'submittedAt',v.submitted_at,'updatedAt',v.updated_at) from public.value_exchange_observations v where v.organization_id=v_org_id and v.project_id=v_project_id and v.workflow_status='submitted'
      union all select jsonb_build_object('id',o.id,'recordType','observation','title',d.label,'workflowStatus',o.workflow_status,'submittedAt',o.submitted_at,'updatedAt',o.updated_at) from public.pmf_observations o join public.pmf_metric_definitions d on d.id=o.definition_id where o.organization_id=v_org_id and o.project_id=v_project_id and o.workflow_status='submitted'
    ) review_rows),'[]'::jsonb),
    'gateSnapshots', coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'pmfLayer',g.pmf_layer,'decision',g.decision,'rationale',g.rationale,'createdAt',g.created_at) order by g.created_at desc) from public.gate_snapshots g where g.organization_id=v_org_id and g.project_id=v_project_id),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_pmf_snapshot() from public, anon;
grant execute on function public.rpc_aoi_pmf_snapshot() to authenticated;

create or replace function public.rpc_aoi_daily_eod_reports(
  p_filters jsonb default '{}'::jsonb,
  p_page integer default 1,
  p_page_size integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 25), 100));
  v_result jsonb;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  join public.organizations organization on organization.id = membership.organization_id
  where membership.user_id = auth.uid() and membership.status = 'active'
    and caller.status = 'active' and not caller.must_change_password
    and organization.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  with filtered as (
    select brief.* from public.daily_eod_briefs brief
    join public.profiles author on author.id = brief.author_id
    left join public.profiles manager on manager.id = brief.engagement_manager_id
    left join public.profiles person_in_charge on person_in_charge.id = brief.person_in_charge_id
    where brief.organization_id = v_org_id and brief.project_id = v_project_id
      and (v_role = 'admin' or brief.author_id = auth.uid())
      and (nullif(p_filters->>'search', '') is null or concat_ws(' ', author.display_name, manager.display_name, person_in_charge.display_name) ilike '%' || trim(p_filters->>'search') || '%')
      and (nullif(p_filters->>'fromDate', '') is null or brief.brief_date >= (p_filters->>'fromDate')::date)
      and (nullif(p_filters->>'toDate', '') is null or brief.brief_date <= (p_filters->>'toDate')::date)
      and (nullif(p_filters->>'authorRole', '') is null or brief.author_role = p_filters->>'authorRole')
      and (nullif(p_filters->>'projectStatus', '') is null or brief.project_status = p_filters->>'projectStatus')
      and (nullif(p_filters->>'workflowStatus', '') is null or brief.workflow_status = p_filters->>'workflowStatus')
  ), paged as (
    select brief.* from filtered brief
    order by brief.brief_date desc, brief.updated_at desc
    limit v_page_size offset (v_page - 1) * v_page_size
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'page', v_page,
    'pageSize', v_page_size,
    'items', coalesce((select jsonb_agg(
      public.daily_eod_brief_json(brief) || jsonb_build_object('auditHistory', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', audit.id, 'action', audit.action, 'actorName', coalesce(actor.display_name, 'AOI'),
          'metadata', audit.metadata, 'createdAt', audit.created_at
        ) order by audit.created_at desc)
        from public.daily_eod_audit_events audit
        left join public.profiles actor on actor.id = audit.actor_id
        where audit.organization_id = brief.organization_id and audit.project_id = brief.project_id
          and audit.brief_id = brief.id
      ), '[]'::jsonb))
      order by brief.brief_date desc, brief.updated_at desc
    ) from paged brief), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) from public, anon;
grant execute on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) to authenticated;

create or replace function private.create_aoi_gate_snapshot(p_pmf_layer text, p_decision text, p_rationale text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_snapshot jsonb;
  v_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  join public.organizations organization on organization.id = membership.organization_id
  where membership.user_id = auth.uid()
    and membership.status = 'active'
    and membership.role = 'admin'
    and profile.status = 'active'
    and not profile.must_change_password
    and organization.status = 'active'
  order by membership.joined_at, membership.organization_id
  limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;

  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id
  limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;
  if p_pmf_layer not in ('H1','H2','H3','H4','H5')
    or p_decision not in ('go','revise','stop','insufficient')
    or length(trim(coalesce(p_rationale, ''))) < 10 then
    raise exception 'GATE_INPUT_INVALID';
  end if;

  v_snapshot := jsonb_build_object(
    'generatedAt', now(),
    'pmfLayer', p_pmf_layer,
    'hypothesis', (select jsonb_build_object(
      'id', hypothesis.id, 'code', hypothesis.code, 'statement', hypothesis.statement,
      'successCriteria', hypothesis.success_criteria, 'decisionStatus', hypothesis.decision_status
    ) from public.hypotheses hypothesis
      where hypothesis.organization_id = v_org_id and hypothesis.project_id = v_project_id
        and hypothesis.pmf_layer = p_pmf_layer limit 1),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object(
      'id', evidence.id, 'respondentId', evidence.respondent_id, 'sessionId', evidence.session_id,
      'segmentId', evidence.segment_id, 'dimension', evidence.dimension, 'title', evidence.title,
      'evidenceText', evidence.evidence_text, 'stance', evidence.stance, 'strength', evidence.strength,
      'sourceLink', evidence.source_link, 'limitations', evidence.limitations
    ) order by evidence.created_at)
      from public.evidence_records evidence
      where evidence.organization_id = v_org_id and evidence.project_id = v_project_id
        and evidence.pmf_layer = p_pmf_layer and evidence.workflow_status = 'approved'
        and (evidence.respondent_id is null or exists (
          select 1 from public.respondents respondent
          where respondent.id = evidence.respondent_id
            and respondent.organization_id = evidence.organization_id
            and respondent.project_id = evidence.project_id
            and respondent.consent_status = 'granted'
        ))), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object(
      'id', observation.id, 'definitionId', observation.definition_id, 'respondentId', observation.respondent_id,
      'sessionId', observation.session_id, 'segmentId', observation.segment_id,
      'numericValue', observation.numeric_value, 'booleanValue', observation.boolean_value,
      'textValue', observation.text_value, 'sourceLink', observation.source_link
    ) order by observation.created_at)
      from public.pmf_observations observation
      join public.pmf_metric_definitions definition on definition.id = observation.definition_id
      where observation.organization_id = v_org_id and observation.project_id = v_project_id
        and definition.organization_id = v_org_id and definition.project_id = v_project_id
        and definition.pmf_layer = p_pmf_layer and observation.workflow_status = 'approved'
        and (observation.respondent_id is null or exists (
          select 1 from public.respondents respondent
          where respondent.id = observation.respondent_id
            and respondent.organization_id = observation.organization_id
            and respondent.project_id = observation.project_id
            and respondent.consent_status = 'granted'
        ))), '[]'::jsonb)
  );

  insert into public.gate_snapshots (
    organization_id, project_id, pmf_layer, decision, rationale, snapshot, created_by
  ) values (
    v_org_id, v_project_id, p_pmf_layer, p_decision, trim(p_rationale), v_snapshot, auth.uid()
  ) returning id into v_id;
  return jsonb_build_object('id', v_id, 'pmfLayer', p_pmf_layer, 'decision', p_decision);
end;
$$;

-- The public Gate RPC is the only authenticated execution path. Its definer
-- ownership can call the private helper without exposing that helper directly.
create or replace function public.rpc_aoi_create_gate_snapshot(
  p_pmf_layer text,
  p_decision text,
  p_rationale text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.create_aoi_gate_snapshot(p_pmf_layer, p_decision, p_rationale);
$$;

revoke all on function private.create_aoi_gate_snapshot(text,text,text) from public, anon, authenticated;
revoke all on function public.rpc_aoi_create_gate_snapshot(text,text,text) from public, anon;
grant execute on function public.rpc_aoi_create_gate_snapshot(text,text,text) to authenticated;

-- Replays remain valid after completion, but never after the associated invited
-- identity has been revoked or bounced. Remove the obsolete token-only overload.
drop function if exists public.rpc_aoi_public_survey_replay(uuid, text, text);
create or replace function public.rpc_aoi_public_survey_replay(
  p_submission_id uuid,
  p_resume_token text,
  p_idempotency_key text,
  p_token text,
  p_invitation_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, extensions
as $$
declare
  v_submission public.survey_submissions;
begin
  select response.* into v_submission
  from public.survey_submissions response
  join public.survey_links link on link.id = response.link_id
  join public.survey_assets asset on asset.id = response.asset_id
  join public.survey_versions version on version.id = response.version_id
  left join public.survey_invitations invitation on invitation.id = response.invitation_id
  where response.id = p_submission_id
    and response.resume_token_hash = digest(p_resume_token, 'sha256')
    and response.idempotency_key = p_idempotency_key
    and response.submitted_at is not null
    and (link.token_hash = digest(p_token, 'sha256') or invitation.token_hash = digest(coalesce(p_invitation_token, ''), 'sha256'))
    and link.link_status = 'active'
    and asset.lifecycle_status = 'published'
    and version.version_status in ('published', 'retired')
    and (link.opens_at is null or link.opens_at <= now())
    and (link.closes_at is null or link.closes_at > now())
    and (response.invitation_id is null or invitation.invitation_status not in ('revoked', 'bounced'))
    and (link.link_mode <> 'invited' or invitation.token_hash = digest(coalesce(p_invitation_token, ''), 'sha256'));
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  return jsonb_build_object('replayed', true, 'submissionId', v_submission.id, 'status', 'submitted', 'submittedAt', v_submission.submitted_at);
end;
$$;

revoke all on function public.rpc_aoi_public_survey_replay(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.rpc_aoi_public_survey_replay(uuid,text,text,text,text) to service_role;

-- Preserve existing collected values. Future direct identifiers are separated
-- from analytical answers, and values are cleared only when their own lifecycle
-- explicitly makes them inactive.
create or replace function private.redact_aoi_direct_identifier_tombstone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_direct_identifier boolean;
begin
  if tg_table_name = 'survey_response_identifiers' then
    if not new.is_active then new.answer_value := 'null'::jsonb; end if;
    return new;
  end if;

  if tg_table_name = 'survey_answers' then
    select exists (
      select 1
      from public.survey_submissions submission
      join public.survey_versions version on version.id = submission.version_id
      cross join lateral jsonb_array_elements(version.definition->'blocks') section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
      where submission.id = new.submission_id
        and question->>'id' = new.question_id
        and question#>>'{privacy,classification}' = 'direct_identifier'
    ) into v_is_direct_identifier;
    if v_is_direct_identifier then
      new.answer_value := 'null'::jsonb;
      new.display_snapshot := '{}'::jsonb;
      new.is_active := false;
    end if;
    return new;
  end if;

  select exists (
    select 1
    from public.survey_answers answer
    join public.survey_submissions submission on submission.id = answer.submission_id
    join public.survey_versions version on version.id = submission.version_id
    cross join lateral jsonb_array_elements(version.definition->'blocks') section
    cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
    where answer.id = new.answer_id
      and not answer.is_active
      and question->>'id' = answer.question_id
      and question#>>'{privacy,classification}' = 'direct_identifier'
  ) into v_is_direct_identifier;
  if v_is_direct_identifier then
    new.previous_value := 'null'::jsonb;
    new.new_value := 'null'::jsonb;
  end if;
  return new;
end;
$$;

revoke all on function private.redact_aoi_direct_identifier_tombstone() from public, anon, authenticated;

drop trigger if exists redact_aoi_direct_identifier_tombstone on public.survey_response_identifiers;
create trigger redact_aoi_direct_identifier_tombstone
before insert or update of answer_value, is_active on public.survey_response_identifiers
for each row execute function private.redact_aoi_direct_identifier_tombstone();

drop trigger if exists redact_aoi_direct_identifier_tombstone on public.survey_answers;
create trigger redact_aoi_direct_identifier_tombstone
before insert or update of answer_value, display_snapshot, is_active on public.survey_answers
for each row execute function private.redact_aoi_direct_identifier_tombstone();

drop trigger if exists redact_aoi_direct_identifier_tombstone on public.survey_answer_revisions;
create trigger redact_aoi_direct_identifier_tombstone
before insert or update of answer_id, previous_value, new_value on public.survey_answer_revisions
for each row execute function private.redact_aoi_direct_identifier_tombstone();

drop policy if exists survey_response_identifiers_assignee_read on public.survey_response_identifiers;
create policy survey_response_identifiers_assignee_read
  on public.survey_response_identifiers for select to authenticated
  using (
    is_active and exists (
      select 1
      from public.survey_submissions submission
      join public.survey_assets asset on asset.id = submission.asset_id
      where submission.id = survey_response_identifiers.submission_id
        and submission.organization_id = survey_response_identifiers.organization_id
        and submission.project_id = survey_response_identifiers.project_id
        and (public.is_org_admin(submission.organization_id) or asset.assigned_to = (select auth.uid()))
    )
  );

revoke all on public.survey_response_identifiers from public, anon, authenticated;
grant select on public.survey_response_identifiers to authenticated;
grant all on public.survey_response_identifiers to service_role;
