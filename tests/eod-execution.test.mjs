import assert from "node:assert/strict";
import test from "node:test";

import { withDisposablePostgres } from "./helpers/supabase-execution-postgres.mjs";

test("EOD snapshot and organization archive execute on the final schema", { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations();
    assert.ok(migrations.some((migration) => migration.endsWith("_eod_aaa_repair.sql")));

    database.execute(fixtures);
    database.query(`select public.rpc_aoi_select_project('${activeProjectId}')`, authenticated(adminId));
    database.query(`select public.rpc_aoi_select_project('${activeProjectId}')`, authenticated(internId));

    assert.equal(database.query(`
      select payload->'dailyEod'->>'projectId' = '${activeProjectId}'
        and payload->'dailyEod'->'myBrief' = 'null'::jsonb
      from (select public.rpc_aoi_daily_eod_snapshot() payload) snapshot
    `, authenticated(internId)), "t");

    const serverDate = database.query(`select public.rpc_aoi_daily_eod_snapshot()->'dailyEod'->>'serverDate'`, authenticated(internId));
    assert.equal(database.query(`
      select saved->>'projectId'='${activeProjectId}' and saved->>'workflowStatus'='draft'
      from (select public.rpc_aoi_save_daily_eod_brief(jsonb_build_object(
        'scopeDate','${serverDate}','scopeProjectId','${activeProjectId}','workflowStatus','draft',
        'engagementManagerId','${adminId}','personInChargeId','${internId}'
      ),null) saved) result
    `, authenticated(internId)), "t");

    assert.equal(database.query(`
      select (payload->>'total')::integer = 3
        and payload->'items' @> '[{"projectCode":"EOD-ACTIVE"},{"projectCode":"EOD-CLOSED"}]'::jsonb
      from (select public.rpc_aoi_daily_eod_reports('{}'::jsonb, 1, 25) payload) reports
    `, authenticated(adminId)), "t");

    assert.equal(database.query(`
      select (payload->>'total')::integer = 2
        and payload->'items' @> '[{"authorId":"${internId}"}]'::jsonb
      from (select public.rpc_aoi_daily_eod_reports('{}'::jsonb, 1, 25) payload) reports
    `, authenticated(internId)), "t");

    database.execute(`update public.daily_eod_briefs set legacy_evidence_missing = true where project_id = '${closedProjectId}'`);
    const legacyId = database.query(`select id from public.daily_eod_briefs where project_id = '${closedProjectId}'`);
    const legacyUpdatedAt = database.query(`select updated_at from public.daily_eod_briefs where id = '${legacyId}'`);
    const legacyPayload = database.query(`select replace(encode(convert_to(public.daily_eod_brief_json(brief)::text, 'UTF8'), 'base64'), E'\\n', '') from public.daily_eod_briefs brief where brief.id = '${legacyId}'`).replaceAll('"', "");
    assert.equal(database.query(`
      select saved->>'workflowStatus' = 'completed'
        and saved->>'legacyEvidenceMissing' = 'true'
        and saved->'evidenceLinks' = '[]'::jsonb
      from (select public.rpc_aoi_admin_update_daily_eod_brief(
        '${legacyId}', convert_from(decode('${legacyPayload}', 'base64'), 'UTF8')::jsonb,
        'Verified imported historical record', '${legacyUpdatedAt}', 'complete'
      ) saved) result
    `, authenticated(adminId)), "t");
  });
});

function authenticated(actor) {
  return { actor, role: "authenticated" };
}

const adminId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const internId = "61616161-6161-4161-8161-616161616161";
const activeProjectId = "62626262-6262-4262-8262-626262626262";
const closedProjectId = "63636363-6363-4363-8363-636363636363";

const fixtures = `
  insert into auth.users (id, email_confirmed_at) values ('${internId}', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password)
  values ('${internId}', 'EOD Intern', 'eod-intern', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status)
  values ('11111111-1111-4111-8111-111111111111', '${internId}', 'intern', 'active');
  insert into public.projects (id, organization_id, code, name, status, lifecycle_status)
  values
    ('${activeProjectId}', '11111111-1111-4111-8111-111111111111', 'EOD-ACTIVE', 'Active EOD Project', 'active', 'active'),
    ('${closedProjectId}', '11111111-1111-4111-8111-111111111111', 'EOD-CLOSED', 'Closed EOD Project', 'complete', 'completed');
  insert into public.project_members (organization_id, project_id, user_id, active, assigned_by)
  values ('11111111-1111-4111-8111-111111111111', '${activeProjectId}', '${internId}', true, '${adminId}');
  insert into public.daily_eod_briefs (
    organization_id, project_id, author_id, author_role, engagement_manager_id, person_in_charge_id,
    brief_date, moved_outcome, evidence_gathered, deliverables_completed, key_insight,
    current_blocker, blocker_impact, proposed_solution, executive_owners, executive_request,
    tomorrow_priorities, project_status, evidence_links, workflow_status, submitted_at
  ) values
    ('11111111-1111-4111-8111-111111111111', '${activeProjectId}', '${adminId}', 'admin', '${adminId}', '${adminId}', current_date,
      'Moved', 'Evidence', 'Delivered', 'Insight', 'None', 'None', 'None', array['None'], 'None', array['One','Two','Three'], 'on_track', '[{"sourceType":"other","label":"Proof","url":"https://example.com/a"}]', 'submitted', now()),
    ('11111111-1111-4111-8111-111111111111', '${closedProjectId}', '${internId}', 'intern', '${adminId}', '${internId}', current_date - 1,
      'Moved', 'Evidence', 'Delivered', 'Insight', 'None', 'None', 'None', array['None'], 'None', array['One','Two','Three'], 'on_track', '[]', 'submitted', now());
`;
