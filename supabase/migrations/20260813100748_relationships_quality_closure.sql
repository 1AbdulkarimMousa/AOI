-- Close the current Relationships data contracts without activating dormant outreach scope.

create or replace function public.rpc_aoi_crm_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
begin
  select project.organization_id into v_org_id
  from public.projects project where project.id = v_project_id;
  select membership.role into v_role
  from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id
    and membership.status = 'active';

  return jsonb_build_object(
    'crmContacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', contact.id, 'candidateId', candidate.id, 'contactType', contact.contact_type,
        'name', contact.name, 'organization', contact.organization_name, 'email', contact.email,
        'phone', contact.phone, 'primaryChannel', contact.primary_channel,
        'sourceUrl', contact.source_url, 'tags', contact.tags,
        'ownerId', contact.owner_id, 'ownerName', owner.display_name,
        'lifecycle', contact.lifecycle, 'nextAction', contact.next_action,
        'nextActionDue', contact.next_action_due, 'priorityScore', contact.priority_score,
        'notes', contact.notes, 'updatedAt', contact.updated_at,
        'outreachStatus', candidate.outreach_status, 'category', candidate.category,
        'pmfCandidate', candidate.pmf_candidate,
        'activityCount', (select count(*) from public.relationship_activities activity
          where activity.organization_id = contact.organization_id
            and activity.project_id = contact.project_id and activity.contact_id = contact.id)
      ) order by contact.next_action_due nulls last, contact.priority_score desc, contact.id)
      from public.crm_contacts contact
      left join public.candidates candidate on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id and candidate.project_id = contact.project_id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.organization_id = v_org_id and contact.project_id = v_project_id
        and (v_role = 'admin' or contact.owner_id = v_actor_id or candidate.id is not null)
    ), '[]'::jsonb),
    'crmActivity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', activity.id, 'contactId', activity.contact_id, 'candidateId', activity.candidate_id,
        'activityType', activity.activity_type, 'summary', activity.summary,
        'channel', activity.channel, 'status', activity.status,
        'actorName', coalesce(actor.display_name, 'AOI'), 'createdAt', activity.occurred_at
      ) order by activity.occurred_at desc, activity.id desc)
      from public.relationship_activities activity
      join public.crm_contacts contact on contact.id = activity.contact_id
        and contact.organization_id = activity.organization_id and contact.project_id = activity.project_id
      left join public.candidates candidate on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id and candidate.project_id = contact.project_id
      left join public.profiles actor on actor.id = activity.actor_id
      where activity.organization_id = v_org_id and activity.project_id = v_project_id
        and (v_role = 'admin' or contact.owner_id = v_actor_id or candidate.id is not null)
    ), '[]'::jsonb),
    'crmProgress', jsonb_build_object(
      'xp', coalesce((select sum(reward.points) from public.crm_reward_events reward
        where reward.project_id = v_project_id and reward.actor_id = v_actor_id), 0),
      'completedToday', coalesce((select count(*) from public.crm_reward_events reward
        where reward.project_id = v_project_id and reward.actor_id = v_actor_id
          and reward.reward_date = current_date), 0),
      'streakDays', coalesce((select count(distinct reward.reward_date)
        from public.crm_reward_events reward where reward.project_id = v_project_id
          and reward.actor_id = v_actor_id and reward.reward_date >= current_date - 6), 0)
    )
  );
end;
$$;

create or replace function public.rpc_aoi_operations_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_campaign public.outreach_campaigns%rowtype;
  v_summary jsonb;
  v_categories jsonb;
  v_recommendations jsonb := '[]'::jsonb;
  v_required_pool integer;
  v_pool_gap integer;
  v_confirmation_gap integer;
begin
  select project.organization_id into v_org_id
  from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id
    and membership.status = 'active';
  select campaign.* into v_campaign from public.outreach_campaigns campaign
  where campaign.organization_id = v_org_id and campaign.project_id = v_project_id;

  v_summary := jsonb_build_object(
    'totalCandidates', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id),
    'contactReady', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.contact_readiness <> 'Research needed'),
    'contacted', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status not in ('Not Contacted','Ready to Send','Unreachable')),
    'responses', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and (candidate.response_date is not null or candidate.outreach_status in ('Replied','Interested','Confirmed','Declined'))),
    'interested', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status in ('Interested','Confirmed')),
    'confirmed', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status = 'Confirmed'),
    'pmfCandidates', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.pmf_candidate),
    'researchNeeded', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.contact_readiness = 'Research needed')
  );
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', grouped.category, 'candidates', grouped.candidates,
    'contactReady', grouped.contact_ready, 'confirmed', grouped.confirmed
  ) order by grouped.category), '[]'::jsonb) into v_categories
  from (
    select candidate.category, count(*) as candidates,
      count(*) filter (where candidate.contact_readiness <> 'Research needed') as contact_ready,
      count(*) filter (where candidate.outreach_status = 'Confirmed') as confirmed
    from public.candidates candidate where candidate.project_id = v_project_id
    group by candidate.category
  ) grouped;

  if v_campaign.id is not null and v_campaign.conversion_rate > 0 then
    v_required_pool := ceil(coalesce(nullif(v_campaign.planning_target, 0), v_campaign.confirmed_target_high)::numeric / v_campaign.conversion_rate)::integer;
    v_pool_gap := greatest(0, v_required_pool - (v_summary->>'totalCandidates')::integer);
    v_confirmation_gap := greatest(0, v_campaign.confirmed_target_low - (v_summary->>'confirmed')::integer);
    if v_pool_gap > 0 then
      v_recommendations := v_recommendations || jsonb_build_array(jsonb_build_object(
        'id', 'pool-gap', 'type', 'pipeline', 'priority', 'critical',
        'title', 'Rebuild the active prospect pool',
        'reason', format('%s active prospects are needed; the current pool has %s.', v_required_pool, v_summary->>'totalCandidates'),
        'action', format('Add %s qualified prospects before sending the next wave.', v_pool_gap)
      ));
    end if;
    if v_confirmation_gap > 0 then
      v_recommendations := v_recommendations || jsonb_build_array(jsonb_build_object(
        'id', 'confirmation-gap', 'type', 'deadline', 'priority', 'critical',
        'title', 'Protect the confirmation deadline',
        'reason', format('%s low-target confirmations are still missing.', v_confirmation_gap),
        'action', 'Prioritize contact-ready candidates with a dated follow-up.'
      ));
    end if;
  end if;
  select coalesce(v_recommendations || jsonb_agg(jsonb_build_object(
    'id', 'category-' || (category->>'name'), 'type', 'category', 'priority', 'high',
    'title', 'Enrich ' || (category->>'name') || ' coverage',
    'reason', format('%s records still need a verified contact route.', (category->>'candidates')::integer - (category->>'contactReady')::integer),
    'action', 'Assign contact research and require a source URL before outreach.'
  )), v_recommendations) into v_recommendations
  from jsonb_array_elements(v_categories) category
  where (category->>'confirmed')::integer = 0
    and (category->>'contactReady')::integer < (category->>'candidates')::integer;

  return jsonb_build_object(
    'campaign', case when v_campaign.id is null then '{}'::jsonb else jsonb_build_object(
      'id', v_campaign.id, 'name', v_campaign.name,
      'preliminaryInterestDeadline', v_campaign.preliminary_interest_deadline,
      'preliminaryInterestTarget', v_campaign.preliminary_interest_target,
      'deadline', v_campaign.confirmation_deadline, 'targetLow', v_campaign.confirmed_target_low,
      'targetHigh', v_campaign.confirmed_target_high, 'planningTarget', v_campaign.planning_target,
      'conversionRate', v_campaign.conversion_rate, 'recommendedActivePool', v_campaign.recommended_active_pool,
      'safetyNotice', v_campaign.safety_notice, 'firstTouchGuidance', v_campaign.first_touch_guidance
    ) end,
    'scoringRules', coalesce(v_campaign.scoring_rules, '{}'::jsonb),
    'outreachSummary', v_summary, 'categories', v_categories, 'recommendations', v_recommendations,
    'executionPlan', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.id, 'date', item.plan_date, 'focus', item.focus,
      'plannedFirstTouches', item.planned_first_touches, 'actualFirstTouches', item.actual_first_touches,
      'plannedFollowUps', item.planned_follow_ups, 'actualFollowUps', item.actual_follow_ups,
      'expectedOutcome', item.expected_outcome, 'owner', item.owner_label
    ) order by item.plan_date) from public.outreach_plan_items item where item.project_id = v_project_id), '[]'::jsonb),
    'emailTemplates', case when v_role = 'admin' then coalesce((select jsonb_agg(jsonb_build_object(
      'id', template.id, 'name', template.name, 'audience', template.audience,
      'subject', template.subject, 'body', template.body, 'status', template.status
    ) order by template.name) from public.email_templates template where template.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'candidates', coalesce((select jsonb_agg(jsonb_build_object(
      'id', candidate.id, 'externalId', coalesce(candidate.external_id, 'AOI-' || candidate.id::text), 'source', candidate.source_label,
      'name', candidate.name, 'category', candidate.category, 'platforms', candidate.platforms,
      'reach', candidate.reach, 'tier', candidate.tier, 'creatorType', candidate.creator_type,
      'contentFit', candidate.content_fit, 'fitLevel', candidate.fit_level,
      'contactReadiness', candidate.contact_readiness, 'contactChannel', candidate.contact_channel,
      'contactDetail', candidate.contact_detail, 'sourceUrl', candidate.source_url,
      'pmfCandidate', candidate.pmf_candidate, 'pmfRationale', candidate.pmf_rationale,
      'priorityScore', candidate.priority_score, 'priorityBand', candidate.priority_band,
      'ownerId', candidate.assigned_to, 'ownerName', owner.display_name,
      'outreachStatus', candidate.outreach_status, 'interestLevel', candidate.interest_level,
      'preferredCollaboration', candidate.preferred_collaboration,
      'deckIntroduced', candidate.deck_introduced, 'pmfAsked', candidate.pmf_asked,
      'firstOutreach', candidate.first_outreach, 'followUp1', candidate.follow_up_1,
      'followUp2', candidate.follow_up_2, 'responseDate', candidate.response_date,
      'nextStep', candidate.next_step, 'nextStepDue', candidate.next_step_due,
      'notes', candidate.notes, 'workflowStatus', candidate.workflow_status,
      'sourceUpdatedOn', candidate.source_updated_on, 'lastUpdated', candidate.updated_at::date,
      'updatedAt', candidate.updated_at
    ) order by candidate.priority_score desc, candidate.next_step_due nulls last, candidate.id)
      from public.candidates candidate left join public.profiles owner on owner.id = candidate.assigned_to
      where candidate.organization_id = v_org_id and candidate.project_id = v_project_id
        and (v_role = 'admin' or candidate.assigned_to = v_actor_id)), '[]'::jsonb),
    'outreachEvents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', event.id, 'candidateId', event.candidate_id, 'channel', event.channel,
      'kind', event.kind, 'status', event.status, 'occurredAt', event.occurred_at,
      'actorName', coalesce(actor.display_name, 'AOI'), 'summary', event.summary
    ) order by event.occurred_at desc, event.id) from public.outreach_events event
      left join public.profiles actor on actor.id = event.actor_id
      where event.organization_id = v_org_id and event.project_id = v_project_id
        and (v_role = 'admin' or event.candidate_id in (
          select candidate.id from public.candidates candidate
          where candidate.project_id = v_project_id and candidate.assigned_to = v_actor_id
        ))), '[]'::jsonb),
    'evidenceRecords', coalesce((select jsonb_agg(jsonb_build_object(
      'id', evidence.id, 'candidateId', evidence.candidate_id, 'type', evidence.type,
      'stance', evidence.stance, 'strength', evidence.strength, 'title', evidence.title,
      'notes', evidence.notes, 'consentStatus', evidence.consent_status,
      'recordedBy', coalesce(recorder.display_name, 'AOI'), 'recordedAt', evidence.recorded_at,
      'workflowStatus', evidence.workflow_status
    ) order by evidence.recorded_at desc, evidence.id) from public.evidence_records evidence
      left join public.profiles recorder on recorder.id = evidence.recorded_by
      where evidence.organization_id = v_org_id and evidence.project_id = v_project_id
        and (v_role = 'admin' or evidence.candidate_id in (
          select candidate.id from public.candidates candidate
          where candidate.project_id = v_project_id and candidate.assigned_to = v_actor_id
        ))), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_crm_contact(contact jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_owner_id uuid;
  v_existing public.crm_contacts%rowtype;
  v_saved public.crm_contacts%rowtype;
  v_candidate public.candidates%rowtype;
  v_create_outreach boolean := coalesce(nullif(contact->>'createOutreach', '')::boolean, false);
  v_points integer := 35;
  v_awarded integer := 0;
begin
  if jsonb_typeof(coalesce(contact, '{}'::jsonb)) <> 'object' then raise exception 'OUTREACH_PAYLOAD_INVALID'; end if;
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';

  if nullif(contact->>'id', '') is not null then
    select existing.* into v_existing from public.crm_contacts existing
    where existing.id = (contact->>'id')::uuid and existing.organization_id = v_org_id
      and existing.project_id = v_project_id for update;
    if v_existing.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
    if v_role <> 'admin' and v_existing.owner_id <> v_actor_id then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
    if nullif(contact->>'updatedAt', '')::timestamptz is null
      or v_existing.updated_at <> (contact->>'updatedAt')::timestamptz then
      raise exception 'OUTREACH_STALE_WRITE';
    end if;
  end if;

  v_owner_id := coalesce(nullif(contact->>'ownerId', '')::uuid, v_existing.owner_id, v_actor_id);
  if v_role <> 'admin' and v_owner_id <> v_actor_id then raise exception 'OUTREACH_REASSIGN_ADMIN_REQUIRED'; end if;
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.organization_id = v_org_id and membership.user_id = v_owner_id
      and membership.status = 'active'
      and private.aoi_actor_can_access_project(v_owner_id, v_org_id, v_project_id)
  ) then raise exception 'OUTREACH_OWNER_INVALID'; end if;
  if length(trim(coalesce(contact->>'name', v_existing.name, ''))) < 2 then raise exception 'CRM_CONTACT_NAME_REQUIRED'; end if;
  if nullif(contact->>'lifecycle', '') is not null
    and contact->>'lifecycle' not in ('new','researching','ready','contacted','engaged','qualified','paused') then
    raise exception 'CRM_LIFECYCLE_INVALID';
  end if;

  if v_existing.id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, organization_name, email, phone,
      primary_channel, source_url, tags, owner_id, lifecycle, next_action,
      next_action_due, priority_score, notes, created_by
    ) values (
      v_org_id, v_project_id, coalesce(nullif(contact->>'contactType', ''), 'KOL'), trim(contact->>'name'),
      nullif(contact->>'organization', ''), nullif(contact->>'email', ''), nullif(contact->>'phone', ''),
      coalesce(nullif(contact->>'primaryChannel', ''), 'Email'), nullif(contact->>'sourceUrl', ''),
      nullif(contact->>'tags', ''), v_owner_id, coalesce(nullif(contact->>'lifecycle', ''), 'new'),
      nullif(contact->>'nextAction', ''), nullif(contact->>'nextActionDue', '')::date,
      greatest(0, least(100, coalesce(nullif(contact->>'priorityScore', '')::integer, 50))),
      nullif(contact->>'notes', ''), v_actor_id
    ) returning * into v_saved;
  else
    update public.crm_contacts existing set
      contact_type = case when contact ? 'contactType' then coalesce(nullif(contact->>'contactType', ''), existing.contact_type) else existing.contact_type end,
      name = case when contact ? 'name' then trim(contact->>'name') else existing.name end,
      organization_name = case when contact ? 'organization' then nullif(contact->>'organization', '') else existing.organization_name end,
      email = case when contact ? 'email' then nullif(contact->>'email', '') else existing.email end,
      phone = case when contact ? 'phone' then nullif(contact->>'phone', '') else existing.phone end,
      primary_channel = case when contact ? 'primaryChannel' then coalesce(nullif(contact->>'primaryChannel', ''), existing.primary_channel) else existing.primary_channel end,
      source_url = case when contact ? 'sourceUrl' then nullif(contact->>'sourceUrl', '') else existing.source_url end,
      tags = case when contact ? 'tags' then nullif(contact->>'tags', '') else existing.tags end,
      owner_id = v_owner_id,
      lifecycle = case when contact ? 'lifecycle' then coalesce(nullif(contact->>'lifecycle', ''), existing.lifecycle) else existing.lifecycle end,
      next_action = case when contact ? 'nextAction' then nullif(contact->>'nextAction', '') else existing.next_action end,
      next_action_due = case when contact ? 'nextActionDue' then nullif(contact->>'nextActionDue', '')::date else existing.next_action_due end,
      priority_score = case when nullif(contact->>'priorityScore', '') is not null then greatest(0, least(100, (contact->>'priorityScore')::integer)) else existing.priority_score end,
      notes = case when contact ? 'notes' then nullif(contact->>'notes', '') else existing.notes end,
      updated_at = clock_timestamp()
    where existing.id = v_existing.id returning existing.* into v_saved;
  end if;

  select candidate.* into v_candidate from public.candidates candidate
  where candidate.organization_id = v_org_id and candidate.project_id = v_project_id
    and candidate.crm_contact_id = v_saved.id;
  if v_candidate.id is not null and v_candidate.assigned_to is distinct from v_owner_id then
    update public.candidates candidate set
      owner_id = v_owner_id, assigned_to = v_owner_id, updated_at = clock_timestamp()
    where candidate.id = v_candidate.id
    returning candidate.* into v_candidate;
  end if;
  if v_create_outreach and v_candidate.id is null then
    insert into public.candidates (
      organization_id, project_id, crm_contact_id, name, category, contact_readiness,
      contact_channel, contact_detail, source_url, priority_score, owner_id, assigned_to,
      outreach_status, next_step, next_step_due, notes, created_by
    ) values (
      v_org_id, v_project_id, v_saved.id, v_saved.name, v_saved.contact_type,
      coalesce(nullif(contact->>'contactReadiness', ''), 'Research needed'), v_saved.primary_channel,
      coalesce(nullif(contact->>'contactDetail', ''), v_saved.email, v_saved.phone), v_saved.source_url,
      v_saved.priority_score, v_owner_id, v_owner_id,
      coalesce(nullif(contact->>'outreachStatus', ''), 'Not Contacted'),
      v_saved.next_action, v_saved.next_action_due, v_saved.notes, v_actor_id
    ) returning * into v_candidate;
  end if;

  insert into public.relationship_activities (
    organization_id, project_id, contact_id, candidate_id, actor_id, activity_type, summary
  ) values (v_org_id, v_project_id, v_saved.id, v_candidate.id, v_actor_id, 'enrich', 'Contact record saved');
  if v_saved.source_url is not null and v_saved.next_action is not null and v_saved.next_action_due is not null then v_points := v_points + 10; end if;
  insert into public.crm_reward_events (organization_id, project_id, contact_id, actor_id, action, points)
  values (v_org_id, v_project_id, v_saved.id, v_actor_id, 'enrich', v_points)
  on conflict do nothing returning points into v_awarded;
  select existing.* into v_saved from public.crm_contacts existing where existing.id = v_saved.id;
  return jsonb_build_object(
    'id', v_saved.id, 'candidateId', v_candidate.id, 'ownerId', v_saved.owner_id,
    'name', v_saved.name, 'rewardPoints', coalesce(v_awarded, 0), 'updatedAt', v_saved.updated_at
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_candidate(p_candidate jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_owner_id uuid;
  v_existing public.candidates%rowtype;
  v_contact public.crm_contacts%rowtype;
  v_saved public.candidates%rowtype;
  v_name text;
begin
  if jsonb_typeof(coalesce(p_candidate, '{}'::jsonb)) <> 'object' then raise exception 'OUTREACH_PAYLOAD_INVALID'; end if;
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';

  if coalesce(p_candidate->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select candidate.* into v_existing from public.candidates candidate
    where candidate.id = (p_candidate->>'id')::uuid and candidate.organization_id = v_org_id
      and candidate.project_id = v_project_id for update;
  elsif nullif(p_candidate->>'externalId', '') is not null then
    select candidate.* into v_existing from public.candidates candidate
    where candidate.project_id = v_project_id and candidate.external_id = p_candidate->>'externalId' for update;
  end if;
  if nullif(p_candidate->>'id', '') is not null and v_existing.id is null
    and coalesce(p_candidate->>'id', '') not like 'local-%' then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if v_existing.id is not null then
    if v_role <> 'admin' and v_existing.assigned_to <> v_actor_id then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
    if nullif(p_candidate->>'updatedAt', '')::timestamptz is null
      or v_existing.updated_at <> (p_candidate->>'updatedAt')::timestamptz then raise exception 'OUTREACH_STALE_WRITE'; end if;
  end if;

  v_owner_id := coalesce(nullif(p_candidate->>'ownerId', '')::uuid, v_existing.assigned_to, v_actor_id);
  if v_role <> 'admin' and v_owner_id <> v_actor_id then raise exception 'OUTREACH_REASSIGN_ADMIN_REQUIRED'; end if;
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.organization_id = v_org_id and membership.user_id = v_owner_id
      and membership.status = 'active'
      and private.aoi_actor_can_access_project(v_owner_id, v_org_id, v_project_id)
  ) then raise exception 'OUTREACH_OWNER_INVALID'; end if;
  v_name := trim(coalesce(p_candidate->>'name', v_existing.name, ''));
  if length(v_name) < 2 then raise exception 'CANDIDATE_NAME_REQUIRED'; end if;

  if v_existing.id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, email, phone, primary_channel,
      source_url, owner_id, lifecycle, next_action, next_action_due, priority_score, notes, created_by
    ) values (
      v_org_id, v_project_id, coalesce(nullif(p_candidate->>'category', ''), 'Other / Discovery'), v_name,
      case when trim(coalesce(p_candidate->>'contactDetail', '')) ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then trim(p_candidate->>'contactDetail') end,
      case when trim(coalesce(p_candidate->>'contactDetail', '')) ~ '^\+?[0-9][0-9 ()-]{5,}[0-9]$' then trim(p_candidate->>'contactDetail') end,
      coalesce(nullif(p_candidate->>'contactChannel', ''), 'Email'), nullif(p_candidate->>'sourceUrl', ''),
      v_owner_id, 'new', nullif(p_candidate->>'nextStep', ''), nullif(p_candidate->>'nextStepDue', '')::date,
      greatest(0, least(100, coalesce(nullif(p_candidate->>'priorityScore', '')::integer, 0))),
      nullif(p_candidate->>'notes', ''), v_actor_id
    ) returning * into v_contact;
    insert into public.candidates (
      organization_id, project_id, crm_contact_id, external_id, source_label, name, category,
      platforms, reach, tier, creator_type, content_fit, fit_level, contact_readiness,
      contact_channel, contact_detail, source_url, pmf_candidate, pmf_rationale,
      priority_score, priority_band, owner_id, assigned_to, outreach_status, interest_level,
      preferred_collaboration, deck_introduced, pmf_asked, first_outreach, follow_up_1,
      follow_up_2, response_date, next_step, next_step_due, notes, source_updated_on, created_by
    ) values (
      v_org_id, v_project_id, v_contact.id,
      coalesce(case when coalesce(p_candidate->>'externalId', '') like 'local-%' then null else nullif(p_candidate->>'externalId', '') end, 'AOI-' || v_contact.id::text),
      nullif(p_candidate->>'source', ''), v_name, coalesce(nullif(p_candidate->>'category', ''), 'Other / Discovery'),
      nullif(p_candidate->>'platforms', ''), nullif(p_candidate->>'reach', ''), nullif(p_candidate->>'tier', ''),
      nullif(p_candidate->>'creatorType', ''), nullif(p_candidate->>'contentFit', ''), nullif(p_candidate->>'fitLevel', ''),
      coalesce(nullif(p_candidate->>'contactReadiness', ''), 'Research needed'), nullif(p_candidate->>'contactChannel', ''),
      nullif(p_candidate->>'contactDetail', ''), nullif(p_candidate->>'sourceUrl', ''),
      coalesce(nullif(p_candidate->>'pmfCandidate', '')::boolean, false), nullif(p_candidate->>'pmfRationale', ''),
      greatest(0, least(100, coalesce(nullif(p_candidate->>'priorityScore', '')::integer, 0))),
      nullif(p_candidate->>'priorityBand', ''), v_owner_id, v_owner_id,
      coalesce(nullif(p_candidate->>'outreachStatus', ''), 'Not Contacted'),
      coalesce(nullif(p_candidate->>'interestLevel', ''), 'Unknown'), nullif(p_candidate->>'preferredCollaboration', ''),
      coalesce(nullif(p_candidate->>'deckIntroduced', '')::boolean, false), coalesce(nullif(p_candidate->>'pmfAsked', '')::boolean, false),
      nullif(p_candidate->>'firstOutreach', '')::date, nullif(p_candidate->>'followUp1', '')::date,
      nullif(p_candidate->>'followUp2', '')::date, nullif(p_candidate->>'responseDate', '')::date,
      nullif(p_candidate->>'nextStep', ''), nullif(p_candidate->>'nextStepDue', '')::date,
      nullif(p_candidate->>'notes', ''), nullif(p_candidate->>'sourceUpdatedOn', '')::date, v_actor_id
    ) returning * into v_saved;
  else
    select contact.* into v_contact from public.crm_contacts contact where contact.id = v_existing.crm_contact_id;
    update public.crm_contacts contact set
      name = case when p_candidate ? 'name' then v_name else contact.name end,
      contact_type = case when p_candidate ? 'category' then coalesce(nullif(p_candidate->>'category', ''), contact.contact_type) else contact.contact_type end,
      owner_id = v_owner_id,
      source_url = case when p_candidate ? 'sourceUrl' then nullif(p_candidate->>'sourceUrl', '') else contact.source_url end,
      next_action = case when p_candidate ? 'nextStep' then nullif(p_candidate->>'nextStep', '') else contact.next_action end,
      next_action_due = case when p_candidate ? 'nextStepDue' then nullif(p_candidate->>'nextStepDue', '')::date else contact.next_action_due end,
      notes = case when p_candidate ? 'notes' then nullif(p_candidate->>'notes', '') else contact.notes end,
      updated_at = clock_timestamp()
    where contact.id = v_contact.id;
    update public.candidates candidate set
      source_label = case when p_candidate ? 'source' then nullif(p_candidate->>'source', '') else candidate.source_label end,
      name = case when p_candidate ? 'name' then v_name else candidate.name end,
      category = case when p_candidate ? 'category' then coalesce(nullif(p_candidate->>'category', ''), candidate.category) else candidate.category end,
      platforms = case when p_candidate ? 'platforms' then nullif(p_candidate->>'platforms', '') else candidate.platforms end,
      reach = case when p_candidate ? 'reach' then nullif(p_candidate->>'reach', '') else candidate.reach end,
      tier = case when p_candidate ? 'tier' then nullif(p_candidate->>'tier', '') else candidate.tier end,
      creator_type = case when p_candidate ? 'creatorType' then nullif(p_candidate->>'creatorType', '') else candidate.creator_type end,
      content_fit = case when p_candidate ? 'contentFit' then nullif(p_candidate->>'contentFit', '') else candidate.content_fit end,
      fit_level = case when p_candidate ? 'fitLevel' then nullif(p_candidate->>'fitLevel', '') else candidate.fit_level end,
      contact_readiness = case when p_candidate ? 'contactReadiness' then coalesce(nullif(p_candidate->>'contactReadiness', ''), candidate.contact_readiness) else candidate.contact_readiness end,
      contact_channel = case when p_candidate ? 'contactChannel' then nullif(p_candidate->>'contactChannel', '') else candidate.contact_channel end,
      contact_detail = case when p_candidate ? 'contactDetail' then nullif(p_candidate->>'contactDetail', '') else candidate.contact_detail end,
      source_url = case when p_candidate ? 'sourceUrl' then nullif(p_candidate->>'sourceUrl', '') else candidate.source_url end,
      pmf_candidate = case when p_candidate ? 'pmfCandidate' then coalesce(nullif(p_candidate->>'pmfCandidate', '')::boolean, false) else candidate.pmf_candidate end,
      pmf_rationale = case when p_candidate ? 'pmfRationale' then nullif(p_candidate->>'pmfRationale', '') else candidate.pmf_rationale end,
      priority_score = case when nullif(p_candidate->>'priorityScore', '') is not null then greatest(0, least(100, (p_candidate->>'priorityScore')::integer)) else candidate.priority_score end,
      priority_band = case when p_candidate ? 'priorityBand' then nullif(p_candidate->>'priorityBand', '') else candidate.priority_band end,
      owner_id = v_owner_id, assigned_to = v_owner_id,
      outreach_status = case when p_candidate ? 'outreachStatus' then coalesce(nullif(p_candidate->>'outreachStatus', ''), candidate.outreach_status) else candidate.outreach_status end,
      interest_level = case when p_candidate ? 'interestLevel' then coalesce(nullif(p_candidate->>'interestLevel', ''), candidate.interest_level) else candidate.interest_level end,
      preferred_collaboration = case when p_candidate ? 'preferredCollaboration' then nullif(p_candidate->>'preferredCollaboration', '') else candidate.preferred_collaboration end,
      deck_introduced = case when p_candidate ? 'deckIntroduced' then coalesce(nullif(p_candidate->>'deckIntroduced', '')::boolean, false) else candidate.deck_introduced end,
      pmf_asked = case when p_candidate ? 'pmfAsked' then coalesce(nullif(p_candidate->>'pmfAsked', '')::boolean, false) else candidate.pmf_asked end,
      first_outreach = case when p_candidate ? 'firstOutreach' then nullif(p_candidate->>'firstOutreach', '')::date else candidate.first_outreach end,
      follow_up_1 = case when p_candidate ? 'followUp1' then nullif(p_candidate->>'followUp1', '')::date else candidate.follow_up_1 end,
      follow_up_2 = case when p_candidate ? 'followUp2' then nullif(p_candidate->>'followUp2', '')::date else candidate.follow_up_2 end,
      response_date = case when p_candidate ? 'responseDate' then nullif(p_candidate->>'responseDate', '')::date else candidate.response_date end,
      next_step = case when p_candidate ? 'nextStep' then nullif(p_candidate->>'nextStep', '') else candidate.next_step end,
      next_step_due = case when p_candidate ? 'nextStepDue' then nullif(p_candidate->>'nextStepDue', '')::date else candidate.next_step_due end,
      notes = case when p_candidate ? 'notes' then nullif(p_candidate->>'notes', '') else candidate.notes end,
      source_updated_on = case when p_candidate ? 'sourceUpdatedOn' then nullif(p_candidate->>'sourceUpdatedOn', '')::date else candidate.source_updated_on end,
      updated_at = clock_timestamp()
    where candidate.id = v_existing.id returning candidate.* into v_saved;
  end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, v_actor_id, 'candidate', v_saved.id, 'upsert', jsonb_build_object('name', v_saved.name));
  return jsonb_build_object(
    'id', v_saved.id, 'externalId', v_saved.external_id, 'name', v_saved.name,
    'category', v_saved.category, 'ownerId', v_saved.assigned_to,
    'outreachStatus', v_saved.outreach_status, 'workflowStatus', v_saved.workflow_status,
    'updatedAt', v_saved.updated_at
  );
end;
$$;

create or replace function public.rpc_aoi_log_outreach(
  p_candidate_id uuid, p_event_channel text, p_event_kind text,
  p_event_status text, p_event_summary text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_candidate public.candidates%rowtype;
  v_event public.outreach_events%rowtype;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  select candidate.* into v_candidate from public.candidates candidate
  where candidate.id = p_candidate_id and candidate.organization_id = v_org_id
    and candidate.project_id = v_project_id;
  if v_candidate.id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if v_role <> 'admin' and v_candidate.assigned_to <> v_actor_id then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
  if length(trim(coalesce(p_event_summary, ''))) < 3 then raise exception 'OUTREACH_ACTIVITY_SUMMARY_REQUIRED'; end if;
  insert into public.outreach_events (
    organization_id, project_id, candidate_id, channel, kind, status, actor_id, summary
  ) values (
    v_org_id, v_project_id, p_candidate_id, p_event_channel,
    coalesce(nullif(p_event_kind, ''), 'Initial'), coalesce(nullif(p_event_status, ''), 'Drafted'),
    v_actor_id, trim(p_event_summary)
  ) returning * into v_event;
  update public.candidates candidate set
    outreach_status = case when p_event_status in ('Sent','Replied','Interested','Confirmed') then p_event_status else candidate.outreach_status end,
    updated_at = clock_timestamp()
  where candidate.id = p_candidate_id;
  return jsonb_build_object('id', v_event.id, 'candidateId', v_event.candidate_id);
end;
$$;

create or replace function public.rpc_aoi_add_evidence(
  p_candidate_id uuid, p_evidence_type text, p_evidence_stance text,
  p_evidence_strength integer, p_evidence_title text, p_evidence_notes text,
  p_evidence_consent text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_candidate public.candidates%rowtype;
  v_result public.evidence_records%rowtype;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  select candidate.* into v_candidate from public.candidates candidate
  where candidate.id = p_candidate_id and candidate.organization_id = v_org_id
    and candidate.project_id = v_project_id;
  if v_candidate.id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if v_role <> 'admin' and v_candidate.assigned_to <> v_actor_id then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
  if length(trim(coalesce(p_evidence_title, ''))) < 2 then raise exception 'EVIDENCE_TITLE_REQUIRED'; end if;
  insert into public.evidence_records (
    organization_id, project_id, candidate_id, type, evidence_type, stance, strength,
    title, notes, consent_status, workflow_status, assigned_to, recorded_by
  ) values (
    v_org_id, v_project_id, p_candidate_id, coalesce(nullif(p_evidence_type, ''), 'PMF interview'),
    coalesce(nullif(p_evidence_type, ''), 'PMF interview'), p_evidence_stance,
    greatest(1, least(4, coalesce(p_evidence_strength, 1))), trim(p_evidence_title),
    nullif(p_evidence_notes, ''), coalesce(nullif(p_evidence_consent, ''), 'pending'),
    'draft', v_actor_id, v_actor_id
  ) returning * into v_result;
  return jsonb_build_object('id', v_result.id, 'candidateId', v_result.candidate_id);
end;
$$;

create or replace function public.rpc_aoi_import_candidates(p_rows jsonb, p_file_name text, p_file_format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_row jsonb;
  v_existing public.candidates%rowtype;
  v_count integer := 0;
  v_job_id uuid;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'IMPORT_ROWS_REQUIRED'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'IMPORT_TOO_LARGE'; end if;
  insert into public.import_jobs (organization_id, project_id, file_name, file_format, row_count, status, created_by)
  values (v_org_id, v_project_id, p_file_name, p_file_format, jsonb_array_length(p_rows), 'previewed', v_actor_id)
  returning id into v_job_id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_existing := null;
    if coalesce(v_row->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      select candidate.* into v_existing from public.candidates candidate
      where candidate.id = (v_row->>'id')::uuid and candidate.organization_id = v_org_id
        and candidate.project_id = v_project_id for update;
    elsif coalesce(v_row->>'externalId', '') ~* '^AOI-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      select candidate.* into v_existing from public.candidates candidate
      where candidate.id = substring(v_row->>'externalId' from 5)::uuid
        and candidate.organization_id = v_org_id and candidate.project_id = v_project_id for update;
    elsif nullif(v_row->>'externalId', '') is not null then
      select candidate.* into v_existing from public.candidates candidate
      where candidate.organization_id = v_org_id and candidate.project_id = v_project_id
        and candidate.external_id = v_row->>'externalId' for update;
    end if;
    if v_existing.id is not null then
      v_row := v_row || jsonb_build_object('id', v_existing.id, 'updatedAt', v_existing.updated_at);
    end if;
    perform public.rpc_aoi_upsert_candidate(v_row);
    v_count := v_count + 1;
  end loop;
  update public.import_jobs set status = 'committed' where id = v_job_id;
  return jsonb_build_object('jobId', v_job_id, 'imported', v_count);
end;
$$;

create or replace function public.rpc_aoi_upsert_participant_recruitment(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_owner_id uuid;
  v_status text;
  v_existing public.participant_recruitment%rowtype;
  v_saved public.participant_recruitment%rowtype;
begin
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then raise exception 'PARTICIPANT_PAYLOAD_INVALID'; end if;
  if p_payload ? 'crmContactId' or p_payload ? 'respondentId' then raise exception 'PARTICIPANT_LINK_MANAGED'; end if;
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  if v_id is not null then
    select item.* into v_existing from public.participant_recruitment item
    where item.id = v_id and item.organization_id = v_org_id and item.project_id = v_project_id for update;
    if v_existing.id is null then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
    if v_role <> 'admin' and v_existing.owner_id <> v_actor_id then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
  end if;
  v_owner_id := coalesce(nullif(p_payload->>'ownerId', '')::uuid, v_existing.owner_id, v_actor_id);
  if v_role <> 'admin' and v_owner_id is distinct from coalesce(v_existing.owner_id, v_actor_id) then
    raise exception 'PARTICIPANT_REASSIGN_ADMIN_REQUIRED';
  end if;
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.organization_id = v_org_id and membership.user_id = v_owner_id
      and membership.status = 'active'
      and private.aoi_actor_can_access_project(v_owner_id, v_org_id, v_project_id)
  ) then raise exception 'PARTICIPANT_OWNER_INVALID'; end if;
  v_status := coalesce(nullif(p_payload->>'status', ''), v_existing.status, 'new');
  if v_status not in ('new','contacted','responded','screening','scheduled','completed','declined','no_response') then
    raise exception 'PARTICIPANT_STATUS_INVALID';
  end if;
  if v_existing.id is not null and v_status is distinct from v_existing.status and not (
    (v_existing.status = 'new' and v_status in ('contacted','declined'))
    or (v_existing.status = 'contacted' and v_status in ('responded','no_response','declined'))
    or (v_existing.status = 'responded' and v_status in ('screening','declined'))
    or (v_existing.status = 'screening' and v_status in ('scheduled','completed','declined'))
    or (v_existing.status = 'scheduled' and v_status in ('completed','declined','no_response'))
  ) then raise exception 'PARTICIPANT_TRANSITION_INVALID'; end if;
  if coalesce(nullif(p_payload->>'consentStatus', ''), v_existing.consent_status, 'pending')
    not in ('pending','granted','declined','withdrawn') then raise exception 'PARTICIPANT_CONSENT_INVALID'; end if;

  if v_existing.id is null then
    if length(trim(coalesce(p_payload->>'participantId', ''))) < 3 then raise exception 'PARTICIPANT_ID_REQUIRED'; end if;
    if length(trim(coalesce(p_payload->>'name', ''))) < 2 then raise exception 'PARTICIPANT_NAME_REQUIRED'; end if;
    insert into public.participant_recruitment (
      organization_id, project_id, participant_id, full_name, email, phone, recruitment_source,
      timezone, status, segment, consent_status, owner_id, next_action, next_action_due,
      interview_date, qualification_notes, notes, created_by
    ) values (
      v_org_id, v_project_id, trim(p_payload->>'participantId'), trim(p_payload->>'name'),
      nullif(trim(p_payload->>'email'), ''), nullif(trim(p_payload->>'phone'), ''),
      coalesce(nullif(trim(p_payload->>'source'), ''), 'Other'), nullif(trim(p_payload->>'timeZone'), ''),
      v_status, nullif(trim(p_payload->>'segment'), ''),
      coalesce(nullif(p_payload->>'consentStatus', ''), 'pending'), v_owner_id,
      nullif(trim(p_payload->>'nextAction'), ''), nullif(p_payload->>'nextActionDue', '')::date,
      nullif(p_payload->>'interviewDate', '')::date, nullif(trim(p_payload->>'qualificationNotes'), ''),
      nullif(trim(p_payload->>'notes'), ''), v_actor_id
    ) returning * into v_saved;
  else
    update public.participant_recruitment item set
      participant_id = case when p_payload ? 'participantId' then trim(p_payload->>'participantId') else item.participant_id end,
      full_name = case when p_payload ? 'name' then trim(p_payload->>'name') else item.full_name end,
      email = case when p_payload ? 'email' then nullif(trim(p_payload->>'email'), '') else item.email end,
      phone = case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'), '') else item.phone end,
      recruitment_source = case when p_payload ? 'source' then coalesce(nullif(trim(p_payload->>'source'), ''), item.recruitment_source) else item.recruitment_source end,
      timezone = case when p_payload ? 'timeZone' then nullif(trim(p_payload->>'timeZone'), '') else item.timezone end,
      status = v_status,
      segment = case when p_payload ? 'segment' then nullif(trim(p_payload->>'segment'), '') else item.segment end,
      consent_status = case when p_payload ? 'consentStatus' then coalesce(nullif(p_payload->>'consentStatus', ''), item.consent_status) else item.consent_status end,
      owner_id = v_owner_id,
      next_action = case when p_payload ? 'nextAction' then nullif(trim(p_payload->>'nextAction'), '') else item.next_action end,
      next_action_due = case when p_payload ? 'nextActionDue' then nullif(p_payload->>'nextActionDue', '')::date else item.next_action_due end,
      interview_date = case when p_payload ? 'interviewDate' then nullif(p_payload->>'interviewDate', '')::date else item.interview_date end,
      qualification_notes = case when p_payload ? 'qualificationNotes' then nullif(trim(p_payload->>'qualificationNotes'), '') else item.qualification_notes end,
      notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
      updated_at = clock_timestamp()
    where item.id = v_existing.id returning item.* into v_saved;
  end if;
  return jsonb_build_object(
    'id', v_saved.id, 'participantId', v_saved.participant_id, 'status', v_saved.status,
    'crmContactId', v_saved.crm_contact_id, 'respondentId', v_saved.respondent_id,
    'ownerId', v_saved.owner_id, 'updatedAt', v_saved.updated_at
  );
end;
$$;

alter function public.rpc_aoi_convert_recruitment_to_respondent(uuid)
  rename to rpc_aoi_convert_recruitment_to_respondent_unscoped;
revoke all on function public.rpc_aoi_convert_recruitment_to_respondent_unscoped(uuid)
  from public, anon, authenticated, service_role;

create function public.rpc_aoi_convert_recruitment_to_respondent(p_recruitment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_recruitment public.participant_recruitment%rowtype;
  v_contact public.crm_contacts%rowtype;
  v_segment public.research_segments%rowtype;
  v_respondent_id uuid;
  v_respondent_code text;
  v_email_matches uuid[];
  v_phone_matches uuid[];
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_CONVERSION_REQUIRED'; end if;
  select recruitment.* into v_recruitment from public.participant_recruitment recruitment
  where recruitment.id = p_recruitment_id and recruitment.organization_id = v_org_id
    and recruitment.project_id = v_project_id for update;
  if v_recruitment.id is null then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
  if v_recruitment.respondent_id is not null then
    return jsonb_build_object(
      'respondentId', v_recruitment.respondent_id, 'crmContactId', v_recruitment.crm_contact_id,
      'alreadyConverted', true
    );
  end if;
  if v_recruitment.status not in ('screening','scheduled','completed') then raise exception 'PARTICIPANT_SCREENING_REQUIRED'; end if;
  if nullif(trim(v_recruitment.segment), '') is null then raise exception 'PARTICIPANT_SEGMENT_REQUIRED'; end if;
  if v_recruitment.consent_status <> 'granted' then raise exception 'PARTICIPANT_CONSENT_REQUIRED'; end if;

  select segment.* into v_segment from public.research_segments segment
  where segment.organization_id = v_org_id and segment.project_id = v_project_id and segment.active
    and (lower(segment.name) = lower(v_recruitment.segment) or lower(segment.code) = lower(v_recruitment.segment))
  order by segment.sequence, segment.id limit 1;
  if v_segment.id is null then raise exception 'PARTICIPANT_SEGMENT_INVALID'; end if;

  if v_recruitment.crm_contact_id is not null then
    select contact.* into v_contact from public.crm_contacts contact
    where contact.id = v_recruitment.crm_contact_id and contact.organization_id = v_org_id
      and contact.project_id = v_project_id;
    if v_contact.id is null then raise exception 'PARTICIPANT_CRM_SCOPE_INVALID'; end if;
  else
    select coalesce(array_agg(contact.id order by contact.updated_at desc), '{}'::uuid[])
    into v_email_matches from public.crm_contacts contact
    where contact.organization_id = v_org_id and contact.project_id = v_project_id
      and nullif(trim(v_recruitment.email), '') is not null
      and lower(contact.email) = lower(trim(v_recruitment.email));
    select coalesce(array_agg(contact.id order by contact.updated_at desc), '{}'::uuid[])
    into v_phone_matches from public.crm_contacts contact
    where contact.organization_id = v_org_id and contact.project_id = v_project_id
      and nullif(regexp_replace(coalesce(v_recruitment.phone, ''), '[^0-9]', '', 'g'), '') is not null
      and regexp_replace(coalesce(contact.phone, ''), '[^0-9]', '', 'g') = regexp_replace(v_recruitment.phone, '[^0-9]', '', 'g');
    if cardinality(v_email_matches) > 1 or cardinality(v_phone_matches) > 1
      or (cardinality(v_email_matches) = 1 and cardinality(v_phone_matches) = 1
        and v_email_matches[1] <> v_phone_matches[1]) then
      raise exception 'CONTACT_IDENTITY_AMBIGUOUS';
    end if;
    select contact.* into v_contact from public.crm_contacts contact
    where contact.id = coalesce(v_email_matches[1], v_phone_matches[1]);
    if v_contact.id is null then
      insert into public.crm_contacts (
        organization_id, project_id, contact_type, name, email, phone, primary_channel,
        tags, owner_id, lifecycle, next_action, next_action_due, priority_score, notes, created_by
      ) values (
        v_org_id, v_project_id, 'Customer', v_recruitment.full_name,
        v_recruitment.email, v_recruitment.phone,
        case when v_recruitment.email is not null then 'Email' else 'Phone' end,
        'research-participant', v_recruitment.owner_id, 'qualified',
        'Complete the first research session', v_recruitment.interview_date,
        70, 'Created from qualified participant recruitment ' || v_recruitment.participant_id, v_actor_id
      ) returning * into v_contact;
    end if;
    update public.participant_recruitment recruitment
    set crm_contact_id = v_contact.id, updated_at = clock_timestamp()
    where recruitment.id = v_recruitment.id;
  end if;

  v_respondent_code := 'CON-' || to_char(current_date, 'YYYY') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  insert into public.respondents (
    organization_id, project_id, external_id, segment_id, respondent_type,
    specialty_status, recruitment_source, consent_status, stage, status,
    workflow_status, assigned_to, created_by, submitted_at, reviewed_by,
    reviewed_at, notes, crm_contact_id, participant_recruitment_id
  ) values (
    v_org_id, v_project_id, v_respondent_code, v_segment.id, 'Consumer',
    nullif(v_recruitment.qualification_notes, ''), v_recruitment.recruitment_source,
    'granted', 'Concept',
    case when v_recruitment.status = 'completed' then 'completed'
      when v_recruitment.status = 'scheduled' then 'scheduled' else 'screening' end,
    'approved', v_recruitment.owner_id, v_actor_id, clock_timestamp(), v_actor_id,
    clock_timestamp(), v_recruitment.notes, v_contact.id, v_recruitment.id
  ) returning id into v_respondent_id;
  insert into public.respondent_contacts (
    respondent_id, organization_id, project_id, contact_name, email, phone,
    contact_reference, preferred_channel, created_by, crm_contact_id
  ) values (
    v_respondent_id, v_org_id, v_project_id, v_recruitment.full_name,
    v_recruitment.email, v_recruitment.phone, v_recruitment.participant_id,
    case when v_recruitment.email is not null then 'Email' else 'Phone' end,
    v_actor_id, v_contact.id
  );
  insert into public.consent_records (
    organization_id, project_id, respondent_id, status, interview_allowed,
    recording_allowed, images_allowed, quotation_allowed, recontact_allowed,
    granted_at, source_reference, recorded_by
  ) values (
    v_org_id, v_project_id, v_respondent_id, 'granted', true,
    false, false, false, false, clock_timestamp(),
    'participant_recruitment:' || v_recruitment.id::text, v_actor_id
  );
  insert into public.contact_external_identities (
    organization_id, project_id, crm_contact_id, namespace, external_id, source, created_by
  ) values
    (v_org_id, v_project_id, v_contact.id, 'recruitment', v_recruitment.participant_id, v_recruitment.recruitment_source, v_actor_id),
    (v_org_id, v_project_id, v_contact.id, 'respondent', v_respondent_code, 'Ambiloop respondent conversion', v_actor_id)
  on conflict (project_id, namespace, external_id) do nothing;
  update public.participant_recruitment recruitment
  set crm_contact_id = v_contact.id, respondent_id = v_respondent_id,
    next_action = 'Open respondent profile and complete the research session',
    updated_at = clock_timestamp()
  where recruitment.id = v_recruitment.id;
  perform private.award_aoi_gamification_event(
    v_org_id, v_project_id, v_actor_id, 'respondent_converted', 40,
    'participant_recruitment', v_recruitment.id,
    jsonb_build_object('respondentId', v_respondent_id, 'participantId', v_recruitment.participant_id)
  );
  return jsonb_build_object(
    'respondentId', v_respondent_id, 'respondentCode', v_respondent_code,
    'crmContactId', v_contact.id, 'participantId', v_recruitment.participant_id,
    'alreadyConverted', false
  );
end;
$$;

drop function public.rpc_aoi_convert_recruitment_to_respondent_unscoped(uuid);

create or replace function public.rpc_aoi_append_consent_version(p_respondent_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_respondent public.respondents%rowtype;
  v_status text := nullif(p_payload->>'status', '');
  v_id uuid;
  v_version integer;
  v_recruitment_id uuid;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select respondent.* into v_respondent from public.respondents respondent
  where respondent.id = p_respondent_id and respondent.organization_id = v_org_id
    and respondent.project_id = v_project_id
    and (public.is_org_admin(v_org_id) or respondent.assigned_to = v_actor_id)
  for update;
  if v_respondent.id is null then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
  if v_status not in ('pending','granted','declined','withdrawn','expired') then raise exception 'CONSENT_STATUS_INVALID'; end if;
  v_recruitment_id := v_respondent.participant_recruitment_id;
  insert into public.consent_records (
    organization_id, project_id, respondent_id, status, interview_allowed,
    recording_allowed, images_allowed, quotation_allowed, recontact_allowed,
    granted_at, withdrawn_at, withdrawal_reason, source_reference, recorded_by
  ) values (
    v_org_id, v_project_id, p_respondent_id, v_status,
    case when v_status = 'granted' then coalesce(nullif(p_payload->>'interviewAllowed', '')::boolean, false) else false end,
    case when v_status = 'granted' then coalesce(nullif(p_payload->>'recordingAllowed', '')::boolean, false) else false end,
    case when v_status = 'granted' then coalesce(nullif(p_payload->>'imagesAllowed', '')::boolean, false) else false end,
    case when v_status = 'granted' then coalesce(nullif(p_payload->>'quotationAllowed', '')::boolean, false) else false end,
    case when v_status = 'granted' and v_recruitment_id is null then coalesce(nullif(p_payload->>'recontactAllowed', '')::boolean, false) else false end,
    case when v_status = 'granted' then clock_timestamp() end,
    case when v_status = 'withdrawn' then clock_timestamp() end,
    nullif(p_payload->>'withdrawalReason', ''),
    case when v_recruitment_id is not null then 'participant_recruitment:' || v_recruitment_id::text end,
    v_actor_id
  ) returning id, version into v_id, v_version;
  if v_recruitment_id is not null then
    update public.participant_recruitment recruitment
    set consent_status = case when v_status in ('granted','declined','withdrawn') then v_status else recruitment.consent_status end,
      updated_at = clock_timestamp()
    where recruitment.id = v_recruitment_id and recruitment.organization_id = v_org_id
      and recruitment.project_id = v_project_id;
  end if;
  return jsonb_build_object('id', v_id, 'respondentId', p_respondent_id, 'version', v_version, 'status', v_status);
end;
$$;

-- Keep the browser-facing CRM activity compatibility call selected-project scoped.
create or replace function public.rpc_aoi_log_crm_activity(
  contact_id uuid, activity_type text, activity_summary text, next_action text default null,
  next_action_due date default null, lifecycle text default null, reward_points integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid;
  v_role text;
  v_contact public.crm_contacts%rowtype;
  v_activity_id uuid;
  v_candidate_id uuid;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  select contact.* into v_contact from public.crm_contacts contact
  where contact.id = rpc_aoi_log_crm_activity.contact_id and contact.organization_id = v_org_id
    and contact.project_id = v_project_id and (v_role = 'admin' or contact.owner_id = v_actor_id);
  if v_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  if activity_type not in ('enrich','outreach','follow_up','qualify','note','status_change','import') then raise exception 'CRM_ACTIVITY_INVALID'; end if;
  if length(trim(coalesce(activity_summary, ''))) < 3 then raise exception 'CRM_ACTIVITY_REQUIRED'; end if;
  if lifecycle is not null and lifecycle not in ('new','researching','ready','contacted','engaged','qualified','paused') then raise exception 'CRM_LIFECYCLE_INVALID'; end if;
  select candidate.id into v_candidate_id from public.candidates candidate
  where candidate.organization_id = v_org_id and candidate.project_id = v_project_id
    and candidate.crm_contact_id = v_contact.id;
  insert into public.relationship_activities (
    organization_id, project_id, contact_id, candidate_id, actor_id, activity_type, summary
  ) values (v_org_id, v_project_id, v_contact.id, v_candidate_id, v_actor_id, activity_type, trim(activity_summary))
  returning id into v_activity_id;
  update public.crm_contacts existing set
    next_action = case when rpc_aoi_log_crm_activity.next_action is not null then nullif(trim(rpc_aoi_log_crm_activity.next_action), '') else existing.next_action end,
    next_action_due = coalesce(rpc_aoi_log_crm_activity.next_action_due, existing.next_action_due),
    lifecycle = coalesce(rpc_aoi_log_crm_activity.lifecycle, existing.lifecycle), updated_at = clock_timestamp()
  where existing.id = v_contact.id;
  return jsonb_build_object('id', v_activity_id, 'contactId', v_contact.id, 'rewardPoints', 0);
end;
$$;

revoke all on function public.rpc_aoi_operations_snapshot() from public, anon, authenticated;
revoke all on function public.rpc_aoi_crm_snapshot() from public, anon, authenticated;
revoke all on function public.rpc_aoi_upsert_crm_contact(jsonb) from public, anon, authenticated;
revoke all on function public.rpc_aoi_upsert_candidate(jsonb) from public, anon, authenticated;
revoke all on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) from public, anon, authenticated;
revoke all on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) from public, anon, authenticated;
revoke all on function public.rpc_aoi_import_candidates(jsonb,text,text) from public, anon, authenticated;
revoke all on function public.rpc_aoi_participant_tracker_snapshot() from public, anon, authenticated;
revoke all on function public.rpc_aoi_upsert_participant_recruitment(jsonb) from public, anon, authenticated;
revoke all on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_append_consent_version(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) from public, anon, authenticated;

grant execute on function public.rpc_aoi_operations_snapshot() to authenticated, service_role;
grant execute on function public.rpc_aoi_crm_snapshot() to authenticated, service_role;
grant execute on function public.rpc_aoi_upsert_crm_contact(jsonb) to authenticated, service_role;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated, service_role;
grant execute on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) to authenticated, service_role;
grant execute on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) to authenticated, service_role;
grant execute on function public.rpc_aoi_import_candidates(jsonb,text,text) to authenticated, service_role;
grant execute on function public.rpc_aoi_participant_tracker_snapshot() to authenticated, service_role;
grant execute on function public.rpc_aoi_upsert_participant_recruitment(jsonb) to authenticated, service_role;
grant execute on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_append_consent_version(uuid,jsonb) to authenticated, service_role;
grant execute on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) to authenticated, service_role;
