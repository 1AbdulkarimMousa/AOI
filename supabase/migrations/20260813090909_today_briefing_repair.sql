-- Authoritative, action-first Today Briefing projection.

alter table public.sample_plan_items
  add column if not exists source_kind text not null default 'unsupported',
  add column if not exists survey_asset_id uuid references public.survey_assets(id) on delete set null;

alter table public.sample_plan_items
  drop constraint if exists sample_plan_items_source_kind_check;
alter table public.sample_plan_items
  add constraint sample_plan_items_source_kind_check check (source_kind in (
    'approved_professional_respondent',
    'approved_consumer_session',
    'approved_product_event_respondent',
    'approved_survey_submission',
    'unsupported'
  ));

update public.sample_plan_items
set source_kind = case label
  when 'Dental professionals' then 'approved_professional_respondent'
  when 'Consumer interviews' then 'approved_consumer_session'
  when 'Product test users' then 'approved_product_event_respondent'
  else 'unsupported'
end
where source_kind = 'unsupported' and survey_asset_id is null;

create index if not exists sample_plan_items_briefing_idx
  on public.sample_plan_items (project_id, source_kind, created_at, id);
create index if not exists tasks_briefing_idx
  on public.tasks (project_id, assigned_to, status, due_date, priority);
create index if not exists project_milestones_briefing_idx
  on public.project_milestones (project_id, owner_id, status, planned_finish, next_action_due);
create index if not exists project_blockers_briefing_idx
  on public.project_blockers (project_id, resolution_owner_id, status, expected_resolution_date, next_action_due);
create index if not exists project_risks_briefing_idx
  on public.project_risks (project_id, owner_id, status, review_date, next_action_due);
create index if not exists project_decisions_briefing_idx
  on public.project_decisions (project_id, owner_id, status, submitted_at);

create function private.aoi_today_attention(
  p_actor_id uuid,
  p_project_id uuid,
  p_role text,
  p_today date
)
returns table (
  source_type text,
  source_id uuid,
  title text,
  reason text,
  category text,
  priority text,
  owner_id uuid,
  due_on date,
  occurred_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from (
    select 'task'::text as source_type, task.id as source_id, task.title,
      case
        when task.status in ('submitted', 'resubmitted') then 'Submitted task is ready for administrator review.'
        when task.status = 'revision_requested' then 'Task revision is assigned back to the owner.'
        when task.status = 'blocked' then 'Task is blocked and needs a clear next action.'
        else 'Task is overdue.'
      end as reason,
      case when task.status in ('submitted', 'resubmitted') then 'review'
        when task.status = 'revision_requested' then 'follow_up'
        when task.status = 'blocked' then 'blocked' else 'overdue' end as category,
      task.priority, task.assigned_to as owner_id, task.due_date as due_on,
      coalesce(task.submitted_at, task.updated_at) as occurred_at
    from public.tasks task
    where task.project_id = p_project_id
      and (p_role = 'admin' or (task.assigned_to = p_actor_id and task.status not in ('submitted', 'resubmitted')))
      and (
        task.status in ('submitted', 'resubmitted', 'revision_requested', 'blocked')
        or (task.due_date < p_today and task.status not in ('completed', 'cancelled'))
      )

    union all
    select 'respondent', record.id, record.external_id,
      'Submitted respondent record is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.respondents record
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'session', record.id, record.method,
      'Submitted research session is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.research_sessions record
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'evidence', record.id, record.title,
      'Submitted evidence is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.evidence_records record
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'product_event', record.id, 'Product event',
      'Submitted product event is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.product_events record
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'value_exchange', record.id, 'Value exchange observation',
      'Submitted value exchange record is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.value_exchange_observations record
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'observation', record.id, definition.label,
      'Submitted PMF observation is ready for review.', 'review', 'medium', record.assigned_to,
      null::date, coalesce(record.submitted_at, record.updated_at)
    from public.pmf_observations record
    join public.pmf_metric_definitions definition on definition.id = record.definition_id
    where record.project_id = p_project_id and record.workflow_status = 'submitted' and p_role = 'admin'

    union all
    select 'survey_version', version.id, coalesce(asset.title->>'en', 'Survey version'),
      'Submitted survey version is ready for review.', 'review', 'medium', version.submitted_by,
      null::date, version.submitted_at
    from public.survey_versions version
    join public.survey_assets asset on asset.id = version.asset_id
    where version.project_id = p_project_id and version.version_status = 'submitted' and p_role = 'admin'

    union all
    select 'survey_submission', submission.id, coalesce(asset.title->>'en', 'Survey response'),
      'Submitted survey response is ready for review.', 'review',
      case when jsonb_array_length(submission.quality_flags) > 0 then 'high' else 'medium' end,
      submission.assigned_to, null::date, submission.submitted_at
    from public.survey_submissions submission
    join public.survey_assets asset on asset.id = submission.asset_id
    where submission.project_id = p_project_id and submission.response_status in ('submitted', 'in_review')
      and (p_role = 'admin' or (submission.response_status = 'in_review' and submission.assigned_to = p_actor_id))

    union all
    select 'milestone', milestone.id, milestone.title,
      case when milestone.status = 'submitted' then 'Submitted milestone is ready for review.'
        when milestone.status = 'blocked' then 'Milestone is blocked.' else 'Milestone deadline is overdue.' end,
      case when milestone.status = 'submitted' then 'review'
        when milestone.status = 'blocked' then 'blocked' else 'overdue' end,
      'medium', milestone.owner_id, least(milestone.next_action_due, milestone.planned_finish),
      coalesce(milestone.submitted_at, milestone.updated_at)
    from public.project_milestones milestone
    where milestone.project_id = p_project_id
      and (p_role = 'admin' or (milestone.owner_id = p_actor_id and milestone.status <> 'submitted'))
      and (milestone.status in ('submitted', 'blocked') or (
        least(milestone.next_action_due, milestone.planned_finish) < p_today
        and milestone.status not in ('completed', 'cancelled')
      ))

    union all
    select 'blocker', blocker.id, blocker.title,
      case when blocker.escalated then 'Escalated blocker needs administrator attention.' else 'Active blocker needs resolution.' end,
      'blocked', blocker.impact, blocker.resolution_owner_id,
      least(blocker.next_action_due, blocker.expected_resolution_date), blocker.blocked_since
    from public.project_blockers blocker
    where blocker.project_id = p_project_id and blocker.status in ('open', 'acknowledged', 'resolving')
      and (p_role = 'admin' or blocker.resolution_owner_id = p_actor_id)

    union all
    select 'risk', risk.id, risk.statement, 'Risk review date is overdue.', 'overdue',
      case when risk.score >= 16 then 'critical' when risk.score >= 10 then 'high'
        when risk.score >= 5 then 'medium' else 'low' end,
      risk.owner_id, risk.review_date, risk.updated_at
    from public.project_risks risk
    where risk.project_id = p_project_id and (p_role = 'admin' or risk.owner_id = p_actor_id)
      and risk.review_date < p_today
      and risk.status not in ('accepted', 'closed')

    union all
    select 'decision', decision.id, decision.title,
      'Submitted decision is ready for governance review.', 'review', 'medium', decision.owner_id,
      null::date, coalesce(decision.submitted_at, decision.updated_at)
    from public.project_decisions decision
    where decision.project_id = p_project_id and decision.status in ('submitted', 'resubmitted') and p_role = 'admin'

    union all
    select 'crm_contact', contact.id, contact.name, 'Relationship next action is overdue.', 'overdue',
      case when contact.priority_score >= 80 then 'high' when contact.priority_score >= 50 then 'medium' else 'low' end,
      contact.owner_id, contact.next_action_due, contact.updated_at
    from public.crm_contacts contact
    where contact.project_id = p_project_id and contact.next_action_due < p_today and contact.lifecycle <> 'paused'
      and (p_role = 'admin' or contact.owner_id = p_actor_id)

    union all
    select 'participant', participant.id, participant.full_name, 'Recruitment next action is overdue.', 'overdue',
      'medium', participant.owner_id, participant.next_action_due, participant.updated_at
    from public.participant_recruitment participant
    where participant.project_id = p_project_id and participant.next_action_due < p_today
      and participant.status not in ('completed', 'declined', 'no_response')
      and (p_role = 'admin' or participant.owner_id = p_actor_id)
  ) attention
  order by case priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
    due_on nulls last, occurred_at nulls last, source_type, source_id;
$$;

revoke all on function private.aoi_today_attention(uuid, uuid, text, date) from public, anon, authenticated;

create function public.rpc_aoi_today_briefing(p_project_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, p_project_id);
  v_organization_id uuid;
  v_role text;
  v_timezone text;
  v_today date;
begin
  select project.organization_id, organization.timezone,
    timezone(organization.timezone, clock_timestamp())::date
  into v_organization_id, v_timezone, v_today
  from public.projects project
  join public.organizations organization on organization.id = project.organization_id
  where project.id = v_project_id;

  select membership.role into v_role
  from public.organization_memberships membership
  where membership.organization_id = v_organization_id
    and membership.user_id = v_actor_id
    and membership.status = 'active';

  return jsonb_build_object(
    'scope', case when v_role = 'admin' then 'team' else 'personal' end,
    'project', (select jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name)
      from public.projects project where project.id = v_project_id),
    'summary', jsonb_build_object(
      'attentionCount', (select count(*) from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today)),
      'pendingReviews', (select count(*) from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today) where category = 'review'),
      'blockedWork', (select count(*) from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today) where category = 'blocked'),
      'overdueTasks', (select count(*) from public.tasks task where task.project_id = v_project_id
        and (v_role = 'admin' or task.assigned_to = v_actor_id) and task.due_date < v_today
        and task.status not in ('completed', 'cancelled')),
      'overdueDeadlines', (select count(*) from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today) where category = 'overdue' and source_type <> 'task'),
      'approvedEvidence', (select count(*) from public.evidence_records evidence
        where evidence.project_id = v_project_id and evidence.workflow_status = 'approved'
          and evidence.consent_status in ('granted', 'not_applicable')
          and (evidence.respondent_id is null or exists (select 1 from public.respondents respondent
            where respondent.id = evidence.respondent_id and respondent.project_id = evidence.project_id
              and respondent.organization_id = evidence.organization_id and respondent.consent_status = 'granted'))),
      'evidenceRespondents', (select count(distinct evidence.respondent_id) from public.evidence_records evidence
        join public.respondents respondent on respondent.id = evidence.respondent_id
          and respondent.project_id = evidence.project_id and respondent.organization_id = evidence.organization_id
        where evidence.project_id = v_project_id and evidence.workflow_status = 'approved'
          and evidence.consent_status in ('granted', 'not_applicable')
          and respondent.consent_status = 'granted')
    ),
    'attention', coalesce((select jsonb_agg(jsonb_build_object(
      'id', attention.source_type || ':' || attention.source_id,
      'sourceType', attention.source_type, 'sourceId', attention.source_id,
      'title', attention.title, 'reason', attention.reason, 'category', attention.category,
      'priority', attention.priority, 'ownerId', attention.owner_id,
      'assetId', case
        when attention.source_type = 'survey_version' then (select version.asset_id from public.survey_versions version where version.id = attention.source_id)
        when attention.source_type = 'survey_submission' then (select submission.asset_id from public.survey_submissions submission where submission.id = attention.source_id)
        else null end,
      'dueOn', attention.due_on, 'occurredAt', attention.occurred_at
    ) order by case attention.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
      attention.due_on nulls last, attention.occurred_at nulls last)
      from (select * from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today) limit 12) attention), '[]'::jsonb),
    'deadlines', coalesce((select jsonb_agg(jsonb_build_object(
      'id', attention.source_type || ':' || attention.source_id,
      'sourceType', attention.source_type, 'sourceId', attention.source_id,
      'title', attention.title, 'dueOn', attention.due_on, 'priority', attention.priority
    ) order by attention.due_on, attention.title)
      from (select * from private.aoi_today_attention(v_actor_id, v_project_id, v_role, v_today)
        where due_on is not null order by due_on, source_type, source_id limit 8) attention), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object(
      'id', sample.id, 'label', sample.label, 'pmfLayer', sample.pmf_layer,
      'actual', case sample.source_kind
        when 'approved_professional_respondent' then (select count(distinct respondent.id) from public.respondents respondent
          where respondent.project_id = v_project_id and respondent.respondent_type = 'Dental Professional'
            and respondent.workflow_status = 'approved' and respondent.consent_status = 'granted'
            and respondent.status not in ('dropped', 'archived'))
        when 'approved_consumer_session' then (select count(distinct session.respondent_id) from public.research_sessions session
          join public.respondents respondent on respondent.id = session.respondent_id
          where session.project_id = v_project_id and session.workflow_status = 'approved'
            and respondent.respondent_type = 'Consumer' and respondent.consent_status = 'granted')
        when 'approved_product_event_respondent' then (select count(distinct event.respondent_id) from public.product_events event
          join public.respondents respondent on respondent.id = event.respondent_id
          where event.project_id = v_project_id and event.workflow_status = 'approved'
            and respondent.consent_status = 'granted')
        when 'approved_survey_submission' then (select count(*) from public.survey_submissions submission
          where submission.project_id = v_project_id and submission.asset_id = sample.survey_asset_id
            and submission.response_status = 'approved'
            and coalesce((submission.consent_receipt->>'accepted')::boolean, false)
            and (submission.respondent_id is null or exists (select 1 from public.respondents respondent
              where respondent.id = submission.respondent_id and respondent.project_id = submission.project_id
                and respondent.organization_id = submission.organization_id and respondent.consent_status = 'granted')))
        else null end,
      'target', sample.target, 'accent', sample.accent, 'sourceKind', sample.source_kind,
      'surveyAssetId', sample.survey_asset_id,
      'derivationStatus', case when sample.source_kind = 'unsupported'
        or (sample.source_kind = 'approved_survey_submission' and sample.survey_asset_id is null)
        then 'unsupported' else 'derived' end
    ) order by sample.created_at, sample.id) from public.sample_plan_items sample
      where sample.project_id = v_project_id), '[]'::jsonb),
    'pmfChain', coalesce((with eligible_evidence as (
      select evidence.* from public.evidence_records evidence
      where evidence.project_id = v_project_id and evidence.workflow_status = 'approved'
        and evidence.consent_status in ('granted', 'not_applicable')
        and (evidence.respondent_id is null or exists (select 1 from public.respondents respondent
          where respondent.id = evidence.respondent_id and respondent.project_id = evidence.project_id
            and respondent.organization_id = evidence.organization_id and respondent.consent_status = 'granted'))
    ), eligible_observations as (
      select observation.*, definition.pmf_layer from public.pmf_observations observation
      join public.pmf_metric_definitions definition on definition.id = observation.definition_id
      where observation.project_id = v_project_id and observation.workflow_status = 'approved'
        and (observation.respondent_id is null or exists (select 1 from public.respondents respondent
          where respondent.id = observation.respondent_id and respondent.project_id = observation.project_id
            and respondent.organization_id = observation.organization_id and respondent.consent_status = 'granted'))
    ) select jsonb_agg(jsonb_build_object(
      'id', layer.id, 'code', layer.code, 'name', layer.name, 'sequence', layer.sequence,
      'supportingCount', (select count(*) from eligible_evidence evidence where evidence.pmf_layer = layer.code and evidence.stance = 'supporting'),
      'contradictingCount', (select count(*) from eligible_evidence evidence where evidence.pmf_layer = layer.code and evidence.stance = 'contradicting'),
      'observationCount', (select count(*) from eligible_observations observation where observation.pmf_layer = layer.code),
      'respondentCount', (select count(distinct respondent_id) from (
        select evidence.respondent_id from eligible_evidence evidence where evidence.pmf_layer = layer.code
        union
        select observation.respondent_id from eligible_observations observation where observation.pmf_layer = layer.code
      ) respondents where respondent_id is not null)
    ) order by layer.sequence) from public.pmf_layers layer where layer.project_id = v_project_id), '[]'::jsonb),
    'evidenceSummary', jsonb_build_object(
      'approved', (select count(*) from public.evidence_records evidence where evidence.project_id = v_project_id
        and evidence.workflow_status = 'approved' and evidence.consent_status in ('granted', 'not_applicable')
        and (evidence.respondent_id is null or exists (
          select 1 from public.respondents respondent where respondent.id = evidence.respondent_id
            and respondent.consent_status = 'granted'))),
      'respondents', (select count(distinct evidence.respondent_id) from public.evidence_records evidence
        join public.respondents respondent on respondent.id = evidence.respondent_id
        where evidence.project_id = v_project_id and evidence.workflow_status = 'approved'
          and evidence.consent_status in ('granted', 'not_applicable')
          and respondent.consent_status = 'granted')
    ),
    'signals', coalesce((select jsonb_agg(jsonb_build_object(
      'id', signal.theme || ':' || signal.stance, 'theme', signal.theme, 'stance', signal.stance,
      'evidenceCount', signal.evidence_count, 'strength', signal.strength
    ) order by signal.evidence_count desc, signal.theme, signal.stance) from (
      select evidence.topic theme, evidence.stance, count(*) evidence_count,
        round(avg(evidence.strength)::numeric, 2) strength
      from public.evidence_records evidence
      where evidence.project_id = v_project_id and evidence.workflow_status = 'approved'
        and evidence.consent_status in ('granted', 'not_applicable')
        and nullif(trim(evidence.topic), '') is not null
        and (evidence.respondent_id is null or exists (select 1 from public.respondents respondent
          where respondent.id = evidence.respondent_id and respondent.project_id = evidence.project_id
            and respondent.organization_id = evidence.organization_id and respondent.consent_status = 'granted'))
      group by evidence.topic, evidence.stance order by count(*) desc, evidence.topic, evidence.stance limit 8
    ) signal), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', activity.id, 'eventType', activity.event_type, 'actorName', activity.actor_name,
      'action', activity.action, 'subject', activity.subject, 'occurredAt', activity.occurred_at,
      'sourceType', activity.source_type, 'sourceId', activity.source_id, 'assetId', activity.asset_id
    ) order by activity.occurred_at desc, activity.id) from (
      select event.id::text, event.event_type, event.actor_name, event.action, event.subject, event.occurred_at,
        null::text source_type, null::uuid source_id, null::uuid asset_id
      from public.activity_events event where event.project_id = v_project_id and v_role = 'admin'
      union all
      select history.id::text, 'task_review', profile.display_name, history.action,
        task.title, history.created_at, 'task', history.task_id, null::uuid
      from public.task_review_history history
      join public.profiles profile on profile.id = history.actor_id
      join public.tasks task on task.id = history.task_id and task.project_id = history.project_id
      where history.project_id = v_project_id and (v_role = 'admin' or task.assigned_to = v_actor_id)
      union all
      select history.id::text, 'project_record', profile.display_name, history.action,
        history.record_type || ':' || history.record_id, history.created_at,
        history.record_type, history.record_id, null::uuid
      from public.project_record_history history join public.profiles profile on profile.id = history.actor_id
      where history.project_id = v_project_id and (v_role = 'admin' or exists (
        select 1 from private.aoi_work_source_context(history.record_type, history.record_id) source
        where source.assigned_to = v_actor_id
      ))
      union all
      select history.id::text, 'research_review', profile.display_name, history.action,
        history.record_type || ':' || history.record_id, history.created_at,
        history.record_type, history.record_id, null::uuid
      from public.research_review_history history join public.profiles profile on profile.id = history.reviewer_id
      where history.project_id = v_project_id and (v_role = 'admin' or exists (
        select 1 from private.aoi_work_source_context(history.record_type, history.record_id) source
        where source.assigned_to = v_actor_id
      ))
      union all
      select review.id::text, 'survey_review', profile.display_name, review.action,
        'survey_submission:' || review.submission_id, review.created_at,
        'survey_submission', review.submission_id, submission.asset_id
      from public.survey_reviews review join public.profiles profile on profile.id = review.reviewer_id
      join public.survey_submissions submission on submission.id = review.submission_id
      where review.project_id = v_project_id and (v_role = 'admin' or exists (
        select 1 from public.survey_submissions submission
        where submission.id = review.submission_id and submission.assigned_to = v_actor_id
      ))
      union all
      select event.id::text, 'crm', coalesce(profile.display_name, 'AOI'), event.activity_type,
        event.summary, event.created_at, 'crm_contact', event.contact_id, null::uuid
      from public.crm_activity event left join public.profiles profile on profile.id = event.actor_id
      where event.project_id = v_project_id and (v_role = 'admin' or exists (
        select 1 from public.crm_contacts contact
        where contact.id = event.contact_id and contact.owner_id = v_actor_id
      ))
      union all
      select event.id::text, 'outreach', coalesce(profile.display_name, 'AOI'),
        event.kind || ':' || event.status, event.summary, event.occurred_at,
        'candidate', event.candidate_id, null::uuid
      from public.outreach_events event left join public.profiles profile on profile.id = event.actor_id
      where event.project_id = v_project_id and (v_role = 'admin' or exists (
        select 1 from public.candidates candidate
        where candidate.id = event.candidate_id and candidate.owner_id = v_actor_id
      ))
      order by occurred_at desc, id limit 12
    ) activity), '[]'::jsonb),
    'generatedAt', clock_timestamp(),
    'timezone', v_timezone
  );
end;
$$;

revoke all on function public.rpc_aoi_today_briefing(uuid) from public, anon;
grant execute on function public.rpc_aoi_today_briefing(uuid) to authenticated, service_role;

comment on function public.rpc_aoi_today_briefing(uuid) is
  'Selected-project Today Briefing derived from maintained source records with administrator/team and intern/personal action scope.';
