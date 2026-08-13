import assert from "node:assert/strict";
import test from "node:test";

import { withDisposablePostgres } from "./helpers/supabase-execution-postgres.mjs";

test("Today Briefing derives selected-project facts with role scope", { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations();
    assert.ok(migrations.some((migration) => migration.endsWith("_today_briefing_repair.sql")));

    const signature = "public.rpc_aoi_today_briefing(uuid)";
    assert.equal(database.query(`
      select has_function_privilege('authenticated', '${signature}', 'execute')
        and has_function_privilege('service_role', '${signature}', 'execute')
        and not has_function_privilege('anon', '${signature}', 'execute')
    `), "t");
    const definition = await database.functionDefinition(signature);
    assert.match(definition, /SECURITY DEFINER/);
    assert.match(definition, /SET search_path TO ''/);
    assert.doesNotMatch(definition, /project_metrics|research_signals|team_progress|sample\.actual|layer\.confidence/i);

    database.execute(fixtures);
    database.query(`select public.rpc_aoi_select_project('${projectId}')`, authenticated(adminId));
    database.query(`select public.rpc_aoi_select_project('${projectId}')`, authenticated(internId));

    assert.equal(database.query(`
      select payload->>'scope' = 'team'
        and (payload->'summary'->>'pendingReviews')::integer >= 1
        and (payload->'summary'->>'blockedWork')::integer >= 1
        and (payload->'summary'->>'overdueTasks')::integer >= 1
        and payload->'attention' @> '[{"sourceId":"${internBlockedTaskId}"}]'::jsonb
        and payload->'attention' @> '[{"sourceId":"${adminReviewTaskId}"}]'::jsonb
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(adminId)), "t");

    assert.equal(database.query(`
      select payload->>'scope' = 'personal'
        and payload->'attention' @> '[{"sourceId":"${internBlockedTaskId}"}]'::jsonb
        and not (payload->'attention' @> '[{"sourceId":"${adminReviewTaskId}"}]'::jsonb)
        and not (payload->'attention' @> '[{"sourceId":"${internSubmittedTaskId}"}]'::jsonb)
        and payload->'attention' @> '[{"sourceId":"${internRevisionTaskId}","category":"follow_up"}]'::jsonb
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(internId)), "t");

    assert.equal(database.query(`
      select (sample->>'actual')::integer = 1
        and sample->>'derivationStatus' = 'derived'
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing,
        lateral jsonb_array_elements(payload->'samplePlan') sample
      where sample->>'sourceKind' = 'approved_professional_respondent'
    `, authenticated(adminId)), "t");

    assert.equal(database.query(`
      select count(*) > 0 and bool_and(sample->'actual' = 'null'::jsonb
        and sample->>'derivationStatus' = 'unsupported')
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing,
        lateral jsonb_array_elements(payload->'samplePlan') sample
      where sample->>'sourceKind' = 'unsupported'
    `, authenticated(adminId)), "t");

    assert.equal(database.query(`
      select (payload->'evidenceSummary'->>'approved')::integer >= 1
        and (payload->'evidenceSummary'->>'respondents')::integer >= 1
        and payload->'signals' @> '[{"theme":"Briefing truth","stance":"supporting"}]'::jsonb
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(adminId)), "t");

    assert.equal(database.query(`
      select payload->'activity' @> '[{"subject":"ADMIN-ACTIVITY-SENTINEL"}]'::jsonb
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(adminId)), "t");
    assert.equal(database.query(`
      select not (payload->'activity' @> '[{"subject":"ADMIN-ACTIVITY-SENTINEL"}]'::jsonb)
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(internId)), "t");

    assert.equal(database.query(`
      select not (payload->'signals' @> '[{"theme":"Pending consent must stay out"}]'::jsonb)
        and (select (layer->>'respondentCount')::integer from jsonb_array_elements(payload->'pmfChain') layer where layer->>'code' = 'H2') >= 1
      from (select public.rpc_aoi_today_briefing('${projectId}') payload) briefing
    `, authenticated(adminId)), "t");
  });
});

function authenticated(actor) {
  return { actor, role: "authenticated" };
}

const adminId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const internId = "51515151-5151-4151-8151-515151515151";
const projectId = "22222222-2222-4222-8222-222222222222";
const internBlockedTaskId = "52525252-5252-4252-8252-525252525252";
const adminReviewTaskId = "53535353-5353-4353-8353-535353535353";
const professionalRespondentId = "54545454-5454-4454-8454-545454545454";
const internSubmittedTaskId = "55555555-5555-4555-8555-555555555555";
const internRevisionTaskId = "56565656-5656-4656-8656-565656565656";

const fixtures = `
  insert into auth.users (id, email_confirmed_at) values ('${internId}', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password)
  values ('${internId}', 'Morgan Example', 'briefing-intern', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status)
  values ('11111111-1111-4111-8111-111111111111', '${internId}', 'intern', 'active');
  insert into public.project_members (organization_id, project_id, user_id, responsibility, active, assigned_by)
  values ('11111111-1111-4111-8111-111111111111', '${projectId}', '${internId}', 'Synthetic briefing contributor', true, '${adminId}');

  insert into public.tasks (
    id, organization_id, project_id, title, objective, status, priority, owner_name,
    owner_initials, assigned_to, created_by, due_date, submitted_at
  ) values
    ('${internBlockedTaskId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
      'Intern blocked fixture', 'Prove personal scope.', 'blocked', 'high', 'Morgan Example', 'ME',
      '${internId}', '${adminId}', '2000-01-01', null),
    ('${adminReviewTaskId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
      'Admin review fixture', 'Prove team scope.', 'submitted', 'critical', 'Migration Test Admin', 'MA',
      '${adminId}', '${adminId}', '2000-01-01', now()),
    ('${internSubmittedTaskId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
      'Intern submitted fixture', 'Submitted work waits for an administrator.', 'submitted', 'medium', 'Morgan Example', 'ME',
      '${internId}', '${adminId}', '2099-01-01', now()),
    ('${internRevisionTaskId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
      'Intern revision fixture', 'Requested revision belongs in personal follow-up.', 'revision_requested', 'high', 'Morgan Example', 'ME',
      '${internId}', '${adminId}', '2099-01-01', now());

  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by
  ) values (
    '${professionalRespondentId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
    'BRIEF-PRO-1', (select id from public.research_segments where project_id = '${projectId}' order by sequence, id limit 1),
    'Dental Professional', 'granted', 'active', 'approved', '${internId}', '${adminId}'
  );
  insert into public.evidence_records (
    organization_id, project_id, respondent_id, type, stance, strength, title, topic,
    evidence_text, consent_status, limitations, workflow_status, assigned_to, recorded_by
  ) values (
    '11111111-1111-4111-8111-111111111111', '${projectId}', '${professionalRespondentId}',
    'interview', 'supporting', 4, 'Authoritative briefing evidence', 'Briefing truth',
    'The action queue matches the source records.', 'granted', 'Synthetic fixture.', 'approved', '${internId}', '${adminId}'
  );
  insert into public.evidence_records (
    organization_id, project_id, type, stance, strength, title, topic, evidence_text,
    consent_status, limitations, workflow_status, assigned_to, recorded_by
  ) values (
    '11111111-1111-4111-8111-111111111111', '${projectId}', 'desk_research', 'supporting', 4,
    'Pending consent evidence', 'Pending consent must stay out', 'This record is not eligible.',
    'pending', 'Synthetic fixture.', 'approved', '${internId}', '${adminId}'
  );
  insert into public.pmf_observations (
    organization_id, project_id, definition_id, respondent_id, segment_id, boolean_value,
    workflow_status, assigned_to, created_by
  ) values (
    '11111111-1111-4111-8111-111111111111', '${projectId}',
    (select id from public.pmf_metric_definitions where project_id = '${projectId}' and pmf_layer = 'H2' order by sequence, id limit 1),
    '${professionalRespondentId}',
    (select segment_id from public.respondents where id = '${professionalRespondentId}'), true,
    'approved', '${internId}', '${adminId}'
  );
  insert into public.activity_events (
    organization_id, project_id, actor_name, actor_initials, action, subject, event_type
  ) values (
    '11111111-1111-4111-8111-111111111111', '${projectId}', 'Avery Example', 'AE',
    'recorded administrator-only project activity', 'ADMIN-ACTIVITY-SENTINEL', 'governance'
  );

  update public.sample_plan_items
  set actual = 999, source_kind = case
    when label = 'Dental professionals' then 'approved_professional_respondent'
    else 'unsupported'
  end, survey_asset_id = null
  where project_id = '${projectId}';
`;
