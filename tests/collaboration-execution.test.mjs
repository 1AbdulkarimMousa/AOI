import assert from 'node:assert/strict';
import test from 'node:test';

import { withDisposablePostgres } from './helpers/supabase-execution-postgres.mjs';

test('durable contextual inbox executes with source-scoped collaboration', { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations({
      async beforeMigration(migration) {
        if (migration.endsWith('_harden_execution_boundaries.sql')) database.execute(preHardeningFixtures);
        if (migration.endsWith('_authoritative_task_lifecycle.sql')) database.execute(preTaskLifecycleFixtures);
        if (migration.endsWith('_contextual_work_inbox.sql')) database.execute(preInboxFixtures);
      },
    });
    assert.ok(migrations.some((migration) => migration.endsWith('_contextual_work_inbox.sql')));

    assert.equal(database.query(`
      select title = 'Preserve inbox source task'
        and status = 'revision_requested'
        and created_at = '2026-08-11 08:00:00+00'::timestamptz
      from public.tasks where id = '${taskId}'
    `), 't');
    assert.equal(database.query(`
      select external_id = 'PRESERVE-INBOX-RESEARCH'
        and notes = 'Preserve this research draft unchanged.'
        and workflow_status = 'draft'
      from public.respondents where id = '${researchId}'
    `), 't');

    assert.equal(database.query(`
      select count(*) = 6 and bool_and(relrowsecurity)
      from pg_class
      where oid = any(array[
        'public.work_inbox_items'::regclass,
        'public.work_comments'::regclass,
        'public.work_comment_revisions'::regclass,
        'public.work_mentions'::regclass,
        'public.work_followers'::regclass,
        'public.work_handoffs'::regclass
      ])
    `), 't');
    assert.equal(database.query(`
      select bool_and(
        has_table_privilege('authenticated', format('public.%I', table_name), 'select')
        and not has_table_privilege('authenticated', format('public.%I', table_name), 'insert')
        and not has_table_privilege('anon', format('public.%I', table_name), 'select')
        and has_table_privilege('service_role', format('public.%I', table_name), 'select,insert,update,delete')
      )
      from (values
        ('work_inbox_items'), ('work_comments'), ('work_comment_revisions'),
        ('work_mentions'), ('work_followers'), ('work_handoffs')
      ) tables(table_name)
    `), 't');

    for (const signature of [
      'public.rpc_aoi_inbox_snapshot(text,uuid)',
      'public.rpc_aoi_mark_inbox_read(uuid)',
      'public.rpc_aoi_create_work_comment(text,uuid,text,uuid,uuid[])',
      'public.rpc_aoi_revise_work_comment(uuid,text,text)',
      'public.rpc_aoi_follow_work_source(text,uuid,boolean)',
      'public.rpc_aoi_handoff_work(text,uuid,uuid,text,uuid)',
    ]) {
      assert.equal(database.query(`
        select has_function_privilege('authenticated', '${signature}', 'execute')
          and has_function_privilege('service_role', '${signature}', 'execute')
          and not has_function_privilege('anon', '${signature}', 'execute')
      `), 't');
      const definition = await database.functionDefinition(signature);
      assert.match(definition, /SECURITY DEFINER/);
      assert.match(definition, /SET search_path TO ''/);
    }

    const firstSnapshot = database.query(`
      select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')
    `, authenticated(internId));
    assert.match(firstSnapshot, /Preserve inbox source task/);
    assert.match(firstSnapshot, /PRESERVE-INBOX-RESEARCH/);
    assert.match(firstSnapshot, /view=today&amp;tab=tasks&amp;task=|view=today&tab=tasks&task=/);
    assert.match(firstSnapshot, /view=research&amp;tab=collect&amp;type=respondent&amp;id=|view=research&tab=collect&type=respondent&id=/);
    assert.equal(database.query(`
      select count(*) from public.work_inbox_items where recipient_id = '${internId}'
    `, authenticated(internId)), '2');
    database.query(`select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')`, authenticated(internId));
    assert.equal(database.query(`
      select count(*) from public.work_inbox_items where recipient_id = '${internId}'
    `, authenticated(internId)), '2');

    assert.equal(database.query(`
      select exists (
        select 1 from jsonb_array_elements(payload->'items') item
        where item->>'sourceId' = '${submittedTaskId}'
          and item->>'reason' = 'Submitted task requires administrator review'
      )
      from (select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}') payload) snapshot
    `, authenticated(adminId)), 't');

    const commentId = database.query(`
      select public.rpc_aoi_create_work_comment(
        'task', '${taskId}', 'Please attach the verified source.', '${commentNonce}',
        array['${internId}'::uuid]
      )->>'id'
    `, authenticated(adminId));
    assert.match(commentId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select public.rpc_aoi_create_work_comment(
        'task', '${taskId}', 'Please attach the verified source.', '${commentNonce}',
        array['${internId}'::uuid]
      )->>'id' = '${commentId}'
    `, authenticated(adminId)), 't');
    assert.equal(database.query(`
      select (select count(*) from public.work_comments where id = '${commentId}') = 1
        and (select count(*) from public.work_comment_revisions where comment_id = '${commentId}') = 1
        and (select count(*) from public.work_mentions where comment_id = '${commentId}') = 1
    `, authenticated(adminId)), 't');
    assert.equal(database.query(`
      select public.rpc_aoi_revise_work_comment(
        '${commentId}', 'Please attach the signed and verified source.', 'Clarified required evidence.'
      )->>'revision'
    `, authenticated(adminId)), '2');
    assert.equal(database.query(`
      select count(*) = 2 and max(revision) = 2
      from public.work_comment_revisions where comment_id = '${commentId}'
    `, authenticated(internId)), 't');

    const unrelatedComment = database.execute(`
      select public.rpc_aoi_create_work_comment(
        'task', '${taskId}', 'I should not see this task.', '${unrelatedNonce}', '{}'::uuid[]
      );
    `, { ...authenticated(unrelatedMemberId), allowFailure: true });
    assert.notEqual(unrelatedComment.status, 0);
    assert.match(unrelatedComment.stderr, /WORK_SOURCE_ACCESS_REQUIRED/);
    assert.equal(database.query(`select count(*) from public.work_comments`, authenticated(unrelatedMemberId)), '0');

    assert.equal(database.query(`
      select public.rpc_aoi_follow_work_source('task', '${taskId}', true)->>'following'
    `, authenticated(internId)), 'true');
    assert.equal(database.query(`
      select public.rpc_aoi_follow_work_source('task', '${taskId}', true)->>'following'
    `, authenticated(internId)), 'true');
    assert.equal(database.query(`
      select count(*) from public.work_followers
      where source_type = 'task' and source_id = '${taskId}' and follower_id = '${internId}'
    `, authenticated(internId)), '1');
    assert.equal(database.query(`
      select jsonb_array_length(public.rpc_aoi_inbox_snapshot('following', '${projectId}')->'items')
    `, authenticated(internId)), '1');

    const handoffId = database.query(`
      select public.rpc_aoi_handoff_work(
        'task', '${taskId}', '${internId}',
        'Please replace the unverified source before resubmission.', '${handoffNonce}'
      )->>'id'
    `, authenticated(adminId));
    assert.match(handoffId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select public.rpc_aoi_handoff_work(
        'task', '${taskId}', '${internId}',
        'Please replace the unverified source before resubmission.', '${handoffNonce}'
      )->>'id' = '${handoffId}'
    `, authenticated(adminId)), 't');
    assert.equal(database.query(`select count(*) from public.work_handoffs where id = '${handoffId}'`), '1');

    const handoffItemId = database.query(`
      select id from public.work_inbox_items
      where recipient_id = '${internId}' and dedupe_key = 'handoff:${handoffId}'
    `, authenticated(internId));
    assert.match(handoffItemId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select public.rpc_aoi_mark_inbox_read('${handoffItemId}')->>'readAt' is not null
    `, authenticated(internId)), 't');
    const markOtherRead = database.execute(`
      select public.rpc_aoi_mark_inbox_read('${handoffItemId}');
    `, { ...authenticated(unrelatedMemberId), allowFailure: true });
    assert.notEqual(markOtherRead.status, 0);
    assert.match(markOtherRead.stderr, /INBOX_ITEM_NOT_FOUND/);

    assert.equal(database.query(`
      select jsonb_array_length(public.rpc_aoi_inbox_snapshot('mentioned', '${projectId}')->'items') = 1
    `, authenticated(internId)), 't');
    assert.equal(database.query(`
      select status = 'revision_requested' from public.tasks where id = '${taskId}'
    `), 't');

    database.execute(`update public.tasks set status = 'completed' where id = '${taskId}';`);
    database.query(`select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')`, authenticated(internId));
    assert.equal(database.query(`
      select handoff.resolved_at is not null and item.resolved_at is not null
      from public.work_handoffs handoff
      join public.work_inbox_items item on item.dedupe_key = 'handoff:' || handoff.id
      where handoff.id = '${handoffId}'
    `), 't');
    database.execute(`update public.tasks set status = 'revision_requested' where id = '${taskId}';`);

    const crossOrganizationHandoff = database.execute(`
      select public.rpc_aoi_handoff_work(
        'task', '${taskId}', '${outsiderId}', 'Cross-organization access attempt.', '${crossOrgNonce}'
      );
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(crossOrganizationHandoff.status, 0);
    assert.match(crossOrganizationHandoff.stderr, /WORK_RECIPIENT_MEMBERSHIP_REQUIRED/);
    assert.equal(database.query(`select count(*) from public.work_inbox_items`, authenticated(outsiderId)), '0');

    const rewriteCommentSource = database.execute(`
      update public.work_comments set source_id = '${submittedTaskId}' where id = '${commentId}';
    `, { ...serviceRole(), allowFailure: true });
    assert.notEqual(rewriteCommentSource.status, 0);
    assert.match(rewriteCommentSource.stderr, /WORK_COLLABORATION_SCOPE_IMMUTABLE/);

    database.execute(`update public.tasks set assigned_to = '${unrelatedMemberId}' where id = '${taskId}';`);
    assert.equal(database.query(`
      select (payload->'counts'->>'following')::integer = 0
        and jsonb_array_length(payload->'items') = 0
      from (select public.rpc_aoi_inbox_snapshot('following', '${projectId}') payload) snapshot
    `, authenticated(internId)), 't');
    assert.equal(database.query(`
      select count(*) from public.work_inbox_items where source_id = '${taskId}'
    `, authenticated(internId)), '0');

    const rewriteRevision = database.execute(`
      update public.work_comment_revisions set body = 'rewritten' where comment_id = '${commentId}';
    `, { ...serviceRole(), allowFailure: true });
    assert.notEqual(rewriteRevision.status, 0);
    assert.match(rewriteRevision.stderr, /WORK_COMMENT_REVISIONS_APPEND_ONLY/);
  });
});

function authenticated(actor) {
  return { actor, role: 'authenticated' };
}

function serviceRole() {
  return { role: 'service_role' };
}

const adminId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const internId = '16161616-1616-4616-8616-161616161616';
const unrelatedMemberId = '17171717-1717-4717-8717-171717171717';
const outsiderId = '18181818-1818-4818-8818-181818181818';
const organizationId = '11111111-1111-4111-8111-111111111111';
const projectId = '22222222-2222-4222-8222-222222222222';
const otherOrganizationId = '19191919-1919-4919-8919-191919191919';
const otherProjectId = '20202020-2020-4020-8020-202020202020';
const taskId = 'e1111111-1111-4111-8111-111111111111';
const submittedTaskId = 'e2222222-2222-4222-8222-222222222222';
const researchId = 'e3333333-3333-4333-8333-333333333333';
const commentNonce = 'e4444444-4444-4444-8444-444444444444';
const unrelatedNonce = 'e5555555-5555-4555-8555-555555555555';
const handoffNonce = 'e6666666-6666-4666-8666-666666666666';
const crossOrgNonce = 'e7777777-7777-4777-8777-777777777777';

const preHardeningFixtures = `
  insert into public.organizations (id, slug, name, status)
  values ('${otherOrganizationId}', 'inbox-other-org', 'Inbox other organization', 'active');
  insert into public.projects (id, organization_id, code, name, status, created_at)
  values ('${otherProjectId}', '${otherOrganizationId}', 'INBOX-OTHER', 'Inbox other project', 'active', '2026-08-01');
`;

const preTaskLifecycleFixtures = `
  insert into auth.users (id, email_confirmed_at) values
    ('${internId}', now()), ('${unrelatedMemberId}', now()), ('${outsiderId}', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password) values
    ('${internId}', 'Inbox Intern', 'inbox-intern', 'active', false),
    ('${unrelatedMemberId}', 'Unrelated Member', 'unrelated-member', 'active', false),
    ('${outsiderId}', 'Outside Member', 'outside-member', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status, joined_at) values
    ('${organizationId}', '${internId}', 'intern', 'active', '2026-08-01'),
    ('${organizationId}', '${unrelatedMemberId}', 'intern', 'active', '2026-08-01'),
    ('${otherOrganizationId}', '${outsiderId}', 'intern', 'active', '2026-08-01');
`;

const preInboxFixtures = `
  insert into public.tasks (
    id, organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, due_date, progress, assigned_to, created_by,
    acceptance_criteria, estimated_hours, created_at, updated_at
  ) values
    (
      '${taskId}', '${organizationId}', '${projectId}', 'Preserve inbox source task',
      'Retain this task while deriving contextual work.', 'revision_requested', 'high',
      'Inbox Intern', 'II', '2026-08-14', 80, '${internId}', '${adminId}',
      'Attach a verified source.', 3.5, '2026-08-11 08:00:00+00', '2026-08-11 09:00:00+00'
    ),
    (
      '${submittedTaskId}', '${organizationId}', '${projectId}', 'Review submitted inbox task',
      'Administrator review remains a source action.', 'submitted', 'critical',
      'Inbox Intern', 'II', '2026-08-13', 100, '${internId}', '${adminId}',
      'Approve or request revision.', 2, '2026-08-11 08:00:00+00', '2026-08-11 09:00:00+00'
    );

  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by, notes, created_at, updated_at
  ) values (
    '${researchId}', '${organizationId}', '${projectId}', 'PRESERVE-INBOX-RESEARCH',
    (select id from public.research_segments where project_id = '${projectId}' order by sequence, id limit 1),
    'Consumer', 'pending', 'recruiting', 'draft', '${internId}', '${internId}',
    'Preserve this research draft unchanged.', '2026-08-11 08:30:00+00', '2026-08-11 09:30:00+00'
  );
`;
