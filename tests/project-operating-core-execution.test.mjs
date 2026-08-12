import assert from 'node:assert/strict';
import test from 'node:test';

import { withDisposablePostgres } from './helpers/supabase-execution-postgres.mjs';

test('project operating core executes with isolated lifecycle and collaboration contracts', { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations({
      async beforeMigration(migration) {
        if (migration.endsWith('_harden_execution_boundaries.sql')) database.execute(preHardeningFixtures);
        if (migration.endsWith('_project_operating_core.sql')) database.execute(preProjectCoreFixtures);
      },
    });
    assert.ok(migrations.some((migration) => migration.endsWith('_project_operating_core.sql')));

    assert.equal(database.query(`
      select name = 'Ambiloop U.S. PMF Validation'
        and code = 'AOI-PMF-01'
        and organization_id = '11111111-1111-4111-8111-111111111111'::uuid
      from public.projects where id = '${projectId}'
    `), 't');
    assert.equal(database.query(`
      select count(*) = 12 and bool_and(relrowsecurity)
      from pg_class
      where oid = any(array[
        'public.project_preferences'::regclass,
        'public.project_members'::regclass,
        'public.project_milestones'::regclass,
        'public.project_blockers'::regclass,
        'public.project_risks'::regclass,
        'public.project_decisions'::regclass,
        'public.project_decision_evidence'::regclass,
        'public.project_decision_snapshots'::regclass,
        'public.project_record_history'::regclass,
        'public.project_history'::regclass,
        'public.project_decision_supersessions'::regclass,
        'public.project_mutation_operations'::regclass
      ])
    `), 't');
    assert.equal(database.query(`
      select bool_and(
        has_table_privilege('authenticated', format('public.%I', table_name), 'select')
        and not has_table_privilege('authenticated', format('public.%I', table_name), 'insert')
        and not has_table_privilege('authenticated', format('public.%I', table_name), 'update')
        and not has_table_privilege('authenticated', format('public.%I', table_name), 'delete')
        and not has_table_privilege('anon', format('public.%I', table_name), 'select')
        and has_table_privilege('service_role', format('public.%I', table_name), 'select,insert,update,delete')
      )
      from (values
        ('project_preferences'), ('project_members'), ('project_milestones'),
        ('project_blockers'), ('project_risks'), ('project_decisions'),
        ('project_decision_evidence'), ('project_decision_snapshots'),
        ('project_record_history'), ('project_history'),
        ('project_decision_supersessions'), ('project_mutation_operations')
      ) tables(table_name)
    `), 't');

    for (const signature of [
      'public.rpc_aoi_project_context()',
      'public.rpc_aoi_select_project(uuid)',
      'public.rpc_aoi_project_snapshot(uuid)',
      'public.rpc_aoi_project_record_detail(text,uuid)',
      'public.rpc_aoi_admin_save_project(jsonb,uuid,timestamp with time zone)',
      'public.rpc_aoi_admin_set_project_member(uuid,uuid,boolean,text,timestamp with time zone)',
      'public.rpc_aoi_transition_project(uuid,text,text,timestamp with time zone)',
      'public.rpc_aoi_save_project_record(text,jsonb,uuid,timestamp with time zone,uuid)',
      'public.rpc_aoi_transition_project_record(text,uuid,text,text,timestamp with time zone,uuid)',
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

    assert.equal(database.query(`
      select count(*) = 1 and bool_and(project_id = '${projectId}'::uuid)
      from public.project_members where user_id = '${internId}' and active
    `), 't');
    assert.equal(database.query(`
      select count(*) from public.project_members where user_id = '${isolatedInternId}' and active
    `), '0');
    assert.equal(database.query(`
      select payload->>'selectedProjectId' is null
        and (payload->>'selectionRequired')::boolean
        and jsonb_array_length(payload->'organizations') = 1
      from (select public.rpc_aoi_project_context() payload) context
    `, authenticated(adminId)), 't');
    const ambiguousSnapshot = database.execute('select public.rpc_aoi_project_snapshot();', {
      ...authenticated(adminId), allowFailure: true,
    });
    assert.notEqual(ambiguousSnapshot.status, 0);
    assert.match(ambiguousSnapshot.stderr, /PROJECT_SELECTION_REQUIRED/);
    assert.equal(database.query(`
      select public.rpc_aoi_select_project('${projectId}')->>'selectedProjectId'
    `, authenticated(adminId)), projectId);
    assert.equal(database.query(`
      select payload->>'selectedProjectId' = '${projectId}'
        and not (payload->>'selectionRequired')::boolean
      from (select public.rpc_aoi_project_context() payload) context
    `, authenticated(adminId)), 't');
    assert.equal(database.query(`select public.rpc_aoi_select_project('${otherProjectId}')->>'selectedProjectId'`, authenticated(adminId)), otherProjectId);
    for (const [snapshot, predicate] of [
      ['public.rpc_aoi_demo_dashboard()', `payload->'project'->>'id' = '${otherProjectId}' and payload->'tasks' @> '[{"id":"${otherProjectTaskId}"}]'::jsonb`],
      ['public.rpc_aoi_operations_snapshot()', `payload->'candidates' @> '[{"id":"${otherProjectCandidateId}"}]'::jsonb`],
      ['public.rpc_aoi_pmf_snapshot()', `payload->'respondents' @> '[{"id":"${otherProjectRespondentId}"}]'::jsonb`],
      ['public.rpc_aoi_crm_snapshot()', `payload->'crmContacts' @> '[{"id":"${otherProjectContactId}"}]'::jsonb`],
      ['public.rpc_aoi_collect_snapshot()', `payload->'respondents' @> '[{"id":"${otherProjectRespondentId}"}]'::jsonb`],
      ['public.rpc_aoi_gamification_summary()', `(payload->>'xp')::integer = 37`],
      ['public.rpc_aoi_daily_eod_snapshot()', `payload->'dailyEod'->'myBrief'->>'id' = '${otherProjectEodId}'`],
      ['public.rpc_aoi_participant_tracker_snapshot()', `payload->>'projectId' = '${otherProjectId}' and payload->'items' @> '[{"id":"${otherProjectParticipantId}"}]'::jsonb`],
      ["public.rpc_aoi_inbox_snapshot('needs_action', null)", `payload->>'projectId' = '${otherProjectId}'`],
    ]) {
      assert.equal(database.query(`select ${predicate} from (select ${snapshot} payload) scoped`, authenticated(adminId)), 't', snapshot);
    }
    assert.equal(database.query(`select public.rpc_aoi_select_project('${projectId}')->>'selectedProjectId'`, authenticated(adminId)), projectId);
    assert.equal(database.query(`
      select payload->>'selectedProjectId' = '${projectId}'
        and jsonb_array_length((payload->'organizations')->0->'projects') = 1
      from (select public.rpc_aoi_project_context() payload) context
    `, authenticated(internId)), 't');

    for (const [actor, deniedProject] of [[internId, otherProjectId], [adminId, foreignProjectId]]) {
      const denied = database.execute(`select public.rpc_aoi_select_project('${deniedProject}');`, {
        ...authenticated(actor), allowFailure: true,
      });
      assert.notEqual(denied.status, 0);
      assert.match(denied.stderr, /PROJECT_NOT_FOUND/);
    }
    assert.equal(database.query(`select count(*) from public.projects`, authenticated(isolatedInternId)), '0');

    const createdProjectId = database.query(`
      select public.rpc_aoi_admin_save_project(jsonb_build_object(
        'code', 'CORE-GOV', 'name', 'Governed project', 'description', 'Lifecycle fixture',
        'objective', 'Exercise authoritative governance.', 'sponsorName', 'Executive sponsor',
        'managerId', '${adminId}', 'plannedStart', '2026-08-12', 'plannedFinish', '2026-09-30',
        'health', 'at_risk'
      ))->>'id'
    `, authenticated(adminId));
    assert.match(createdProjectId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select lifecycle_status = 'planning' and health = 'at_risk'
        and objective = 'Exercise authoritative governance.' and sponsor_name = 'Executive sponsor'
        and manager_id = '${adminId}'::uuid and planned_start = '2026-08-12'::date
      from public.projects where id = '${createdProjectId}'
    `), 't');
    const internProjectSave = database.execute(`
      select public.rpc_aoi_admin_save_project('{"code":"NOPE","name":"Denied"}');
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(internProjectSave.status, 0);
    assert.match(internProjectSave.stderr, /PROJECT_ADMIN_REQUIRED|PROJECT_ORGANIZATION_REQUIRED/);
    assert.equal(database.query(`
      select public.rpc_aoi_admin_set_project_member(
        '${createdProjectId}', '${internId}', true, 'Delivery owner'
      )->>'active'
    `, authenticated(adminId)), 'true');
    const ownerRemoval = database.execute(`
      select public.rpc_aoi_admin_set_project_member('${createdProjectId}', '${adminId}', false, null);
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(ownerRemoval.status, 0);
    assert.match(ownerRemoval.stderr, /PROJECT_OWNER_REMOVAL_FORBIDDEN/);

    const activateProjectAt = updatedAt(database, 'projects', createdProjectId);
    assert.equal(database.query(`
      select public.rpc_aoi_transition_project('${createdProjectId}', 'activate', null, '${activateProjectAt}')->>'lifecycle_status'
    `, authenticated(adminId)), 'active');
    const projectBlockerId = save(database, 'blocker', {
      projectId: createdProjectId, title: 'Critical governance blocker', resolutionOwnerId: internId, impact: 'critical',
    }, adminId);
    const blockedCompletion = database.execute(`
      select public.rpc_aoi_transition_project(
        '${createdProjectId}', 'complete', null, (select updated_at from public.projects where id = '${createdProjectId}')
      );
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(blockedCompletion.status, 0);
    assert.match(blockedCompletion.stderr, /PROJECT_COMPLETION_BLOCKED/);
    transition(database, 'blocker', projectBlockerId, 'resolve', 'The critical governance issue is fully resolved.', adminId);
    for (const [action, note, status] of [
      ['hold', 'Paused for a documented governance dependency.', 'on_hold'],
      ['resume', null, 'active'],
      ['complete', null, 'completed'],
      ['archive', null, 'archived'],
    ]) {
      const sqlNote = note === null ? 'null' : `'${note}'`;
      assert.equal(database.query(`
        select public.rpc_aoi_transition_project(
          '${createdProjectId}', '${action}', ${sqlNote}, (select updated_at from public.projects where id = '${createdProjectId}')
        )->>'lifecycle_status'
      `, authenticated(adminId)), status);
    }
    assert.equal(database.query(`select public.rpc_aoi_project_snapshot('${createdProjectId}')->'project'->>'id'`, authenticated(internId)), createdProjectId);
    const archivedWrite = database.execute(`
      select public.rpc_aoi_save_project_record('risk', jsonb_build_object(
        'projectId', '${createdProjectId}', 'statement', 'Archived writes must fail',
        'ownerId', '${internId}', 'probability', 1, 'impact', 1
      ));
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(archivedWrite.status, 0);
    assert.match(archivedWrite.stderr, /PROJECT_READ_ONLY/);
    assert.equal(database.query(`
      select public.rpc_aoi_transition_project(
        '${createdProjectId}', 'restore', 'Restored for controlled follow-up.',
        (select updated_at from public.projects where id = '${createdProjectId}')
      )->>'lifecycle_status'
    `, authenticated(adminId)), 'completed');
    assert.equal(database.query(`
      select string_agg(action || ':' || to_status, ',' order by created_at, id)
      from public.project_history where project_id = '${createdProjectId}'
    `, authenticated(internId)), '"activate:active,hold:on_hold,resume:active,complete:completed,archive:archived,restore:completed"');

    const inaccessibleOwner = database.execute(`
      select public.rpc_aoi_save_project_record('risk', jsonb_build_object(
        'projectId', '${projectId}', 'statement', 'An inaccessible owner must be rejected.',
        'ownerId', '${isolatedInternId}', 'probability', 2, 'impact', 2
      ));
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(inaccessibleOwner.status, 0);
    assert.match(inaccessibleOwner.stderr, /PROJECT_RECORD_OWNER_REQUIRED/);

    for (const table of [
      'project_members', 'project_milestones', 'project_blockers', 'project_risks',
      'project_decisions', 'project_decision_evidence', 'project_decision_snapshots',
      'project_record_history', 'project_history', 'project_decision_supersessions',
    ]) {
      assert.equal(database.query(`select count(*) from public.${table} where project_id = '${projectId}'`, authenticated(isolatedInternId)), '0', table);
      assert.equal(database.query(`select count(*) from public.${table} where organization_id = '${foreignOrganizationId}'`, authenticated(internId)), '0', table);
    }
    assert.equal(database.query(`select count(*) from public.project_preferences where user_id = '${adminId}'`, authenticated(internId)), '0');
    assert.equal(database.query(`select count(*) from public.project_mutation_operations`, authenticated(isolatedInternId)), '0');

    for (const recordType of ['milestone', 'decision']) {
      const internCreate = database.execute(`
        select public.rpc_aoi_save_project_record('${recordType}', jsonb_build_object(
          'projectId', '${projectId}', 'title', 'Intern-created ${recordType}', 'ownerId', '${internId}'
        ));
      `, { ...authenticated(internId), allowFailure: true });
      assert.notEqual(internCreate.status, 0);
      assert.match(internCreate.stderr, /PROJECT_ADMIN_REQUIRED/);
    }

    const milestoneId = save(database, 'milestone', {
      projectId,
      title: 'Evidence review complete',
      intendedOutcome: 'Approve the verified evidence packet.',
      ownerId: internId,
      plannedFinish: '2026-08-20',
      progressPercent: 60,
      acceptanceCriteria: 'Signed evidence packet attached.',
      nextAction: 'Submit the packet for review.',
      nextActionDue: '2026-08-18',
    }, adminId);
    transition(database, 'milestone', milestoneId, 'activate', null, adminId);
    transition(database, 'milestone', milestoneId, 'block', 'Evidence review is waiting on the signed packet.', internId);
    transition(database, 'milestone', milestoneId, 'unblock', null, internId);
    const milestoneBeforeUpdate = updatedAt(database, 'project_milestones', milestoneId);
    assert.equal(database.query(`
      select public.rpc_aoi_save_project_record(
        'milestone', '{"progressPercent":100,"nextAction":"Review submitted packet."}',
        '${milestoneId}', '${milestoneBeforeUpdate}'
      )->>'id'
    `, authenticated(internId)), milestoneId);
    const staleMilestone = database.execute(`
      select public.rpc_aoi_save_project_record(
        'milestone', '{"progressPercent":80}', '${milestoneId}', '${milestoneBeforeUpdate}'
      );
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(staleMilestone.status, 0);
    assert.match(staleMilestone.stderr, /PROJECT_RECORD_STALE_WRITE/);
    transition(database, 'milestone', milestoneId, 'submit', 'Acceptance criteria met and packet attached.', internId);
    transition(database, 'milestone', milestoneId, 'revise', 'Add the collection date to the signed source.', adminId);
    transition(database, 'milestone', milestoneId, 'submit', 'Added the collection date and resubmitted.', internId);
    transition(database, 'milestone', milestoneId, 'approve', 'Verified against the signed source.', adminId);
    transition(database, 'milestone', milestoneId, 'complete', 'Outcome accepted.', adminId);
    assert.equal(database.query(`select status from public.project_milestones where id = '${milestoneId}'`), 'completed');
    const cancelledMilestoneId = save(database, 'milestone', {
      projectId, title: 'Cancelled milestone fixture', ownerId: internId,
    }, adminId);
    transition(database, 'milestone', cancelledMilestoneId, 'cancel', 'The outcome was removed from the approved scope.', adminId);

    const createNonce = '34343434-3434-4434-8434-343434343434';
    const nonceRiskPayload = {
      projectId, statement: 'Retry-safe risk creation', ownerId: internId, probability: 2, impact: 3,
    };
    const nonceRiskId = save(database, 'risk', nonceRiskPayload, adminId, createNonce);
    assert.equal(save(database, 'risk', nonceRiskPayload, adminId, createNonce), nonceRiskId);
    assert.equal(database.query(`select count(*) from public.project_risks where id = '${nonceRiskId}'`), '1');
    const nonceMismatch = database.execute(`
      select public.rpc_aoi_save_project_record('risk', jsonb_build_object(
        'projectId', '${projectId}', 'statement', 'Different payload', 'ownerId', '${internId}',
        'probability', 2, 'impact', 3
      ), null, null, '${createNonce}');
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(nonceMismatch.status, 0);
    assert.match(nonceMismatch.stderr, /PROJECT_IDEMPOTENCY_MISMATCH/);
    const transitionNonce = '35353535-3535-4535-8535-353535353535';
    const transitionExpectedAt = updatedAt(database, 'project_risks', nonceRiskId);
    const firstTransition = transition(database, 'risk', nonceRiskId, 'assess', null, internId, transitionNonce);
    const replayTransition = database.query(`
      select public.rpc_aoi_transition_project_record(
        'risk', '${nonceRiskId}', 'assess', null, '${transitionExpectedAt}', '${transitionNonce}'
      )->>'updated_at'
    `, authenticated(internId));
    assert.equal(replayTransition, firstTransition.updatedAt);
    assert.equal(database.query(`
      select count(*) = 1 from public.project_record_history
      where record_type = 'risk' and record_id = '${nonceRiskId}' and action = 'assess'
    `), 't');

    const blockerId = save(database, 'blocker', {
      projectId,
      title: 'Consent export unavailable',
      description: 'The signed consent export cannot be retrieved.',
      resolutionOwnerId: internId,
      impact: 'critical',
      nextAction: 'Recover the signed export.',
      nextActionDue: '2026-08-15',
    }, adminId);
    const unauthorizedBlockerEdit = database.execute(`
      select public.rpc_aoi_save_project_record(
        'blocker', '{"description":"Unauthorized edit"}', '${blockerId}',
        (select updated_at from public.project_blockers where id = '${blockerId}')
      );
    `, { ...authenticated(isolatedInternId), allowFailure: true });
    assert.notEqual(unauthorizedBlockerEdit.status, 0);
    assert.match(unauthorizedBlockerEdit.stderr, /PROJECT_RECORD_NOT_FOUND|PROJECT_BLOCKER_EDIT_FORBIDDEN/);
    const internBlockerReassign = database.execute(`
      select public.rpc_aoi_save_project_record(
        'blocker', jsonb_build_object('resolutionOwnerId', '${adminId}'), '${blockerId}',
        (select updated_at from public.project_blockers where id = '${blockerId}')
      );
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(internBlockerReassign.status, 0);
    assert.match(internBlockerReassign.stderr, /PROJECT_BLOCKER_REASSIGN_ADMIN_REQUIRED/);
    const invalidBlockerSource = database.execute(`
      select public.rpc_aoi_save_project_record('blocker', jsonb_build_object(
        'projectId', '${projectId}', 'title', 'Invalid source', 'resolutionOwnerId', '${internId}',
        'sourceType', 'task', 'sourceId', '${otherProjectTaskId}'
      ));
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(invalidBlockerSource.status, 0);
    assert.match(invalidBlockerSource.stderr, /PROJECT_BLOCKER_SOURCE_INVALID/);
    transition(database, 'blocker', blockerId, 'acknowledge', null, internId);
    transition(database, 'blocker', blockerId, 'start_resolving', null, internId);
    const escalationWithoutNote = database.execute(`
      select public.rpc_aoi_transition_project_record(
        'blocker', '${blockerId}', 'escalate', null,
        (select updated_at from public.project_blockers where id = '${blockerId}')
      );
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(escalationWithoutNote.status, 0);
    assert.match(escalationWithoutNote.stderr, /PROJECT_TRANSITION_NOTE_REQUIRED/);
    transition(database, 'blocker', blockerId, 'escalate', 'Consent review is blocked beyond the due date.', internId);
    assert.equal(database.query(`
      select exists (
        select 1 from jsonb_array_elements(public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')->'items') item
        where item->>'sourceType' = 'blocker' and item->>'sourceId' = '${blockerId}'
          and item->>'reason' = 'Escalated blocker requires administrator attention'
      )
    `, authenticated(adminId)), 't');
    transition(database, 'blocker', blockerId, 'resolve', 'Recovered and checksum-verified the signed export.', internId);
    transition(database, 'blocker', blockerId, 'reopen', 'The recovered export is missing one signature page.', internId);
    assert.equal(database.query(`
      select status = 'open' and resolution_note is not null and escalated_at is not null
      from public.project_blockers where id = '${blockerId}'
    `), 't');

    const riskId = save(database, 'risk', {
      projectId,
      statement: 'The validation sample may miss the target segment.',
      ownerId: internId,
      probability: 4,
      impact: 3,
      triggerCondition: 'Recruitment remains below 80 percent.',
      mitigation: 'Open the reserve recruitment channel.',
      nextAction: 'Review reserve candidates.',
      reviewDate: '2026-08-15',
    }, adminId);
    assert.equal(database.query(`select score from public.project_risks where id = '${riskId}'`), '12');
    transition(database, 'risk', riskId, 'assess', null, internId);
    transition(database, 'risk', riskId, 'mitigate', null, internId);
    transition(database, 'risk', riskId, 'monitor', null, internId);
    transition(database, 'risk', riskId, 'close', 'The reserve channel restored the required sample.', internId);
    const acceptedRiskId = save(database, 'risk', {
      projectId,
      statement: 'A small scheduling variance may remain.',
      ownerId: internId,
      probability: 2,
      impact: 2,
      mitigation: 'Keep one reserve interview slot.',
    }, adminId);
    const internRiskAcceptance = database.execute(`
      select public.rpc_aoi_transition_project_record(
        'risk', '${acceptedRiskId}', 'accept', 'The bounded variance is within the approved tolerance.',
        (select updated_at from public.project_risks where id = '${acceptedRiskId}')
      );
    `, { ...authenticated(internId), allowFailure: true });
    assert.notEqual(internRiskAcceptance.status, 0);
    assert.match(internRiskAcceptance.stderr, /PROJECT_TRANSITION_INVALID|PROJECT_ADMIN_REQUIRED/);
    transition(database, 'risk', acceptedRiskId, 'accept', 'The bounded variance is within the approved tolerance.', adminId);

    const decisionId = save(database, 'decision', {
      projectId,
      title: 'Use verified interview evidence',
      statement: 'Use the verified interview evidence for the next validation gate.',
      ownerId: internId,
      decisionMakerId: adminId,
      alternatives: ['Delay the gate', 'Use unverified notes'],
      rationale: 'The signed source is current and directly addresses the hypothesis.',
      expectedImpact: 'The gate remains traceable without delaying the project.',
      evidenceLinks: [{ evidenceId: eligibleEvidenceId, stance: 'supporting', relevanceNote: 'Direct signed evidence.' }],
    }, adminId);
    transition(database, 'decision', decisionId, 'submit', null, internId);
    transition(database, 'decision', decisionId, 'request_revision', 'Explain why delaying the gate is not preferred.', adminId);
    const decisionRevisionAt = updatedAt(database, 'project_decisions', decisionId);
    assert.equal(database.query(`
      select public.rpc_aoi_save_project_record(
        'decision', '{"rationale":"The signed source is current; delaying would add no new eligible evidence."}',
        '${decisionId}', '${decisionRevisionAt}'
      )->>'id'
    `, authenticated(internId)), decisionId);
    transition(database, 'decision', decisionId, 'resubmit', null, internId);
    transition(database, 'decision', decisionId, 'approve', 'Approved from eligible evidence.', adminId);
    assert.equal(database.query(`
      select count(*) = 1
        and bool_and(snapshot->'evidence'->0->>'sourceId' = '${eligibleEvidenceId}')
        and bool_and(snapshot->'evidence'->0->>'stance' = 'supporting')
        and bool_and(snapshot->'evidence'->0 ? 'provenance')
        and bool_and((snapshot->'evidence'->0->>'evidenceApprovedAt')::timestamptz = '2026-08-11 15:00:00+00'::timestamptz)
        and bool_and(snapshot->'evidence'->0->'consent'->>'status' = 'granted')
        and bool_and(snapshot->'evidence'->0->'consent'->>'version' = '1')
        and bool_and(snapshot->'evidence'->0->'consent'->>'recordedAt' is not null)
      from public.project_decision_snapshots where decision_id = '${decisionId}'
    `), 't');
    assert.equal(database.query(`
      select evidence->0->>'title' = 'Eligible signed evidence'
        and evidence->0->>'stance' = 'supporting'
        and evidence->0->>'relevanceNote' = 'Direct signed evidence.'
        and evidence->0 ? 'provenance' and evidence->0 ? 'limitations'
      from (select public.rpc_aoi_project_record_detail('decision', '${decisionId}')->'evidence' evidence) detail
    `, authenticated(internId)), 't');
    const rewriteSnapshot = database.execute(`
      update public.project_decision_snapshots set snapshot = '{}' where decision_id = '${decisionId}';
    `, { ...serviceRole(), allowFailure: true });
    assert.notEqual(rewriteSnapshot.status, 0);
    assert.match(rewriteSnapshot.stderr, /PROJECT_DECISION_SNAPSHOT_IMMUTABLE/);

    const replacementDecisionId = save(database, 'decision', {
      projectId,
      title: 'Use expanded verified evidence',
      statement: 'Use the expanded verified evidence set for the next validation gate.',
      ownerId: internId,
      decisionMakerId: adminId,
      alternatives: ['Retain the original evidence set'],
      rationale: 'The expanded eligible set adds current contradictory coverage.',
      expectedImpact: 'The validation gate reflects the current evidence state.',
      evidenceLinks: [{ evidenceId: eligibleEvidenceId, stance: 'supporting', relevanceNote: 'Current eligible source.' }],
    }, adminId);
    transition(database, 'decision', replacementDecisionId, 'submit', null, internId);
    transition(database, 'decision', replacementDecisionId, 'approve', 'Approved replacement decision.', adminId);
    transition(database, 'decision', decisionId, 'supersede', replacementDecisionId, adminId);
    assert.equal(database.query(`
      select status = 'superseded' and superseded_by_decision_id = '${replacementDecisionId}'::uuid
        and (select count(*) from public.project_decision_snapshots snapshot
          where snapshot.decision_id in ('${decisionId}'::uuid, '${replacementDecisionId}'::uuid)) = 2
      from public.project_decisions where id = '${decisionId}'
    `), 't');
    assert.equal(database.query(`
      select predecessor_decision_id = '${decisionId}'::uuid
        and successor_decision_id = '${replacementDecisionId}'::uuid
        and predecessor_snapshot_id is not null and successor_snapshot_id is not null
      from public.project_decision_supersessions where predecessor_decision_id = '${decisionId}'
    `), 't');
    assert.equal(database.query(`
      select jsonb_array_length(public.rpc_aoi_project_record_detail('decision', '${decisionId}')->'supersessions') = 1
    `, authenticated(internId)), 't');
    for (const mutation of [
      `update public.project_decision_supersessions set successor_decision_id = '${decisionId}' where predecessor_decision_id = '${decisionId}'`,
      `delete from public.project_decision_supersessions where predecessor_decision_id = '${decisionId}'`,
    ]) {
      const immutableSupersession = database.execute(mutation, { ...serviceRole(), allowFailure: true });
      assert.notEqual(immutableSupersession.status, 0);
      assert.match(immutableSupersession.stderr, /PROJECT_DECISION_SUPERSESSION_IMMUTABLE/);
    }

    const ineligibleDecisionId = save(database, 'decision', {
      projectId,
      title: 'Use withdrawn evidence',
      statement: 'Use evidence whose participant withdrew consent.',
      ownerId: internId,
      alternatives: ['Do not use it'],
      rationale: 'This must be rejected by eligibility checks.',
      expectedImpact: 'No withdrawn evidence should enter a snapshot.',
      evidenceLinks: [{ evidenceId: ineligibleEvidenceId, stance: 'supporting', relevanceNote: 'Withdrawn source.' }],
    }, adminId);
    transition(database, 'decision', ineligibleDecisionId, 'submit', null, internId);
    const ineligibleApproval = database.execute(`
      select public.rpc_aoi_transition_project_record(
        'decision', '${ineligibleDecisionId}', 'approve', 'Should fail.',
        (select updated_at from public.project_decisions where id = '${ineligibleDecisionId}')
      );
    `, { ...authenticated(adminId), allowFailure: true });
    assert.notEqual(ineligibleApproval.status, 0);
    assert.match(ineligibleApproval.stderr, /PROJECT_DECISION_EVIDENCE_INELIGIBLE/);

    const rejectedDecisionId = save(database, 'decision', {
      projectId, title: 'Unnecessary delay', statement: 'Delay the validation gate.', ownerId: internId,
      alternatives: ['Proceed now'], rationale: 'Test the rejection lifecycle.', expectedImpact: 'One-week delay.',
    }, adminId);
    transition(database, 'decision', rejectedDecisionId, 'submit', null, internId);
    transition(database, 'decision', rejectedDecisionId, 'reject', 'Delay is not supported by eligible evidence.', adminId);

    assert.equal(database.query(`
      select payload->'project'->>'id' = '${projectId}'
        and jsonb_array_length(payload->'members') >= 2
        and jsonb_array_length(payload->'milestones') >= 1
        and jsonb_array_length(payload->'blockers') >= 1
        and jsonb_array_length(payload->'risks') >= 2
        and jsonb_array_length(payload->'decisions') >= 4
        and payload ? 'summary' and payload ? 'activity'
      from (select public.rpc_aoi_project_snapshot() payload) snapshot
    `, authenticated(adminId)), 't');
    assert.equal(database.query(`
      select payload->>'recordType' = 'milestone' and payload->'record'->>'id' = '${milestoneId}'
      from (select public.rpc_aoi_project_record_detail('milestone', '${milestoneId}') payload) detail
    `, authenticated(internId)), 't');

    const commentId = database.query(`
      select public.rpc_aoi_create_work_comment(
        'blocker', '${blockerId}', 'Please verify the missing signature page.', '${commentNonce}',
        array['${internId}'::uuid]
      )->>'id'
    `, authenticated(adminId));
    assert.match(commentId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select public.rpc_aoi_follow_work_source('risk', '${acceptedRiskId}', true)->>'following'
    `, authenticated(internId)), 'true');
    const handoffId = database.query(`
      select public.rpc_aoi_handoff_work(
        'blocker', '${blockerId}', '${internId}', 'Recover and verify the missing signature page.', '${handoffNonce}'
      )->>'id'
    `, authenticated(adminId));
    assert.match(handoffId, /^[0-9a-f-]{36}$/);
    assert.equal(database.query(`
      select deep_link like 'workspace.html?view=projects&project=${projectId}&tab=%'
      from public.work_inbox_items where dedupe_key = 'handoff:${handoffId}'
    `), 't');

    const reviewMilestoneId = save(database, 'milestone', {
      projectId, title: 'Review inbox fixture', ownerId: internId,
      acceptanceCriteria: 'Review-ready outcome.', progressPercent: 100,
    }, adminId);
    transition(database, 'milestone', reviewMilestoneId, 'submit', 'Review-ready outcome attached.', internId);
    assert.equal(database.query(`
      select exists (
        select 1 from jsonb_array_elements(public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')->'items') item
        where item->>'sourceType' = 'milestone' and item->>'sourceId' = '${reviewMilestoneId}'
          and item->>'reason' = 'Submitted milestone requires administrator review'
      )
    `, authenticated(adminId)), 't');
    transition(database, 'milestone', reviewMilestoneId, 'approve', 'Review complete.', adminId);
    database.query(`select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')`, authenticated(adminId));
    assert.equal(database.query(`
      select resolved_at is not null from public.work_inbox_items
      where recipient_id = '${adminId}' and dedupe_key = 'derived:review:milestone:${reviewMilestoneId}'
    `), 't');
    transition(database, 'blocker', blockerId, 'resolve', 'Recovered the complete signed export.', internId);
    database.query(`select public.rpc_aoi_inbox_snapshot('needs_action', '${projectId}')`, authenticated(internId));
    assert.equal(database.query(`
      select handoff.resolved_at is not null and item.resolved_at is not null
      from public.work_handoffs handoff
      join public.work_inbox_items item on item.dedupe_key = 'handoff:' || handoff.id
      where handoff.id = '${handoffId}'
    `), 't');
  });
});

function authenticated(actor) {
  return { actor, role: 'authenticated' };
}

function serviceRole() {
  return { role: 'service_role' };
}

function save(database, recordType, payload, actor, nonce = null) {
  const serialized = JSON.stringify(payload).replaceAll("'", "''");
  const sqlNonce = nonce === null ? 'null' : `'${nonce}'`;
  const id = database.query(`
    select public.rpc_aoi_save_project_record('${recordType}', '${serialized}'::jsonb, null, null, ${sqlNonce})->>'id'
  `, authenticated(actor));
  assert.match(id, /^[0-9a-f-]{36}$/);
  return id;
}

function transition(database, recordType, recordId, action, note, actor, nonce = null) {
  const table = {
    milestone: 'project_milestones', blocker: 'project_blockers',
    risk: 'project_risks', decision: 'project_decisions',
  }[recordType];
  const sqlNote = note === null ? 'null' : `'${note.replaceAll("'", "''")}'`;
  const sqlNonce = nonce === null ? 'null' : `'${nonce}'`;
  const payload = database.query(`
    select (transitioned.payload->>'status') || '|' || (transitioned.payload->>'updated_at')
    from (select public.rpc_aoi_transition_project_record(
      '${recordType}', '${recordId}', '${action}', ${sqlNote},
      (select updated_at from public.${table} where id = '${recordId}'), ${sqlNonce}
    ) payload) transitioned
  `, authenticated(actor));
  const [status, updatedAt] = payload.split('|');
  return { status, updatedAt };
}

function updatedAt(database, table, id) {
  return database.query(`select updated_at from public.${table} where id = '${id}'`);
}

const adminId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const internId = '21212121-2121-4121-8121-212121212121';
const isolatedInternId = '23232323-2323-4323-8323-232323232323';
const projectId = '22222222-2222-4222-8222-222222222222';
const otherProjectId = '24242424-2424-4424-8424-242424242424';
const otherProjectTaskId = '36363636-3636-4636-8636-363636363636';
const otherProjectCandidateId = '37373737-3737-4737-8737-373737373737';
const otherProjectContactId = '38383838-3838-4838-8838-383838383838';
const otherProjectRespondentId = '39393939-3939-4939-8939-393939393939';
const otherProjectParticipantId = '40404040-4040-4040-8040-404040404040';
const otherProjectEodId = '41414141-4141-4141-8141-414141414141';
const foreignOrganizationId = '25252525-2525-4525-8525-252525252525';
const foreignProjectId = '26262626-2626-4626-8626-262626262626';
const assignedTaskId = '27272727-2727-4727-8727-272727272727';
const eligibleRespondentId = '28282828-2828-4828-8828-282828282828';
const withdrawnRespondentId = '29292929-2929-4929-8929-292929292929';
const eligibleEvidenceId = '30303030-3030-4030-8030-303030303030';
const ineligibleEvidenceId = '31313131-3131-4131-8131-313131313131';
const commentNonce = '32323232-3232-4232-8232-323232323232';
const handoffNonce = '33333333-3333-4333-8333-333333333334';

const preHardeningFixtures = `
  insert into public.organizations (id, slug, name, status)
  values ('${foreignOrganizationId}', 'project-core-foreign', 'Project core foreign organization', 'active');
  insert into public.projects (id, organization_id, code, name, status, created_at)
  values ('${foreignProjectId}', '${foreignOrganizationId}', 'CORE-FOREIGN', 'Foreign project', 'active', '2026-08-01');
`;

const preProjectCoreFixtures = `
  insert into public.projects (id, organization_id, code, name, status, created_at)
  values ('${otherProjectId}', '11111111-1111-4111-8111-111111111111', 'CORE-OTHER', 'Other AOI project', 'active', '2026-08-02');

  insert into auth.users (id, email_confirmed_at) values ('${internId}', now()), ('${isolatedInternId}', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password) values
    ('${internId}', 'Project Core Intern', 'project-core-intern', 'active', false),
    ('${isolatedInternId}', 'Isolated Project Intern', 'isolated-project-intern', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status, joined_at) values
    ('11111111-1111-4111-8111-111111111111', '${internId}', 'intern', 'active', '2026-08-01'),
    ('11111111-1111-4111-8111-111111111111', '${isolatedInternId}', 'intern', 'active', '2026-08-01');

  insert into public.tasks (
    id, organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, assigned_to, created_by, created_at, updated_at
  ) values (
    '${assignedTaskId}', '11111111-1111-4111-8111-111111111111', '${projectId}',
    'Historical project authorization', 'Preserve deterministic assigned access.', 'in_progress', 'medium',
    'Project Core Intern', 'PC', '${internId}', '${adminId}', '2026-08-10', '2026-08-10'
  );

  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by
  ) values
    (
      '${eligibleRespondentId}', '11111111-1111-4111-8111-111111111111', '${projectId}', 'CORE-ELIGIBLE',
      (select id from public.research_segments where project_id = '${projectId}' order by sequence, id limit 1),
      'Consumer', 'granted', 'active', 'approved', '${internId}', '${adminId}'
    ),
    (
      '${withdrawnRespondentId}', '11111111-1111-4111-8111-111111111111', '${projectId}', 'CORE-WITHDRAWN',
      (select id from public.research_segments where project_id = '${projectId}' order by sequence, id limit 1),
      'Consumer', 'withdrawn', 'archived', 'approved', '${internId}', '${adminId}'
    );
  insert into public.consent_records (
    organization_id, project_id, respondent_id, version, status,
    interview_allowed, quotation_allowed, recorded_by
  ) values
    ('11111111-1111-4111-8111-111111111111', '${projectId}', '${eligibleRespondentId}', 1, 'granted', true, true, '${adminId}'),
    ('11111111-1111-4111-8111-111111111111', '${projectId}', '${withdrawnRespondentId}', 1, 'withdrawn', false, false, '${adminId}');
  insert into public.evidence_records (
    id, organization_id, project_id, respondent_id, type, stance, strength, title,
    evidence_text, consent_status, source_link, limitations, workflow_status, assigned_to, recorded_by, reviewed_at
  ) values
    (
      '${eligibleEvidenceId}', '11111111-1111-4111-8111-111111111111', '${projectId}', '${eligibleRespondentId}',
      'interview', 'supporting', 4, 'Eligible signed evidence', 'Verified participant statement.',
      'granted', 'https://example.test/eligible', 'One synthetic participant.', 'approved', '${internId}', '${adminId}', '2026-08-11 15:00:00+00'
    ),
    (
      '${ineligibleEvidenceId}', '11111111-1111-4111-8111-111111111111', '${projectId}', '${withdrawnRespondentId}',
      'interview', 'supporting', 4, 'Withdrawn evidence', 'This must not enter a snapshot.',
      'granted', 'https://example.test/withdrawn', 'Consent was withdrawn.', 'approved', '${internId}', '${adminId}', '2026-08-11 15:00:00+00'
    );

  insert into public.tasks (
    id, organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, assigned_to, created_by
  ) values (
    '${otherProjectTaskId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}',
    'OTHER-PROJECT-SENTINEL-TASK', 'Canonical snapshot sentinel.', 'in_progress', 'high',
    'Migration Test Admin', 'MA', '${adminId}', '${adminId}'
  );
  insert into public.crm_contacts (
    id, organization_id, project_id, name, owner_id, created_by
  ) values (
    '${otherProjectContactId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}',
    'OTHER-PROJECT-SENTINEL-CONTACT', '${adminId}', '${adminId}'
  );
  insert into public.candidates (
    id, organization_id, project_id, crm_contact_id, name, category, owner_id, assigned_to, created_by
  ) values (
    '${otherProjectCandidateId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}', '${otherProjectContactId}',
    'OTHER-PROJECT-SENTINEL-CANDIDATE', 'Sentinel', '${adminId}', '${adminId}', '${adminId}'
  );
  insert into public.research_segments (
    organization_id, project_id, code, name, audience_type, sequence
  ) values (
    '11111111-1111-4111-8111-111111111111', '${otherProjectId}', 'sentinel',
    'Other project sentinel', 'consumer', 1
  );
  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by
  ) values (
    '${otherProjectRespondentId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}',
    'OTHER-PROJECT-SENTINEL-RESPONDENT',
    (select id from public.research_segments where project_id = '${otherProjectId}' and code = 'sentinel'),
    'Consumer', 'granted', 'active', 'draft', '${adminId}', '${adminId}'
  );
  insert into public.participant_recruitment (
    id, organization_id, project_id, participant_id, full_name, owner_id, created_by
  ) values (
    '${otherProjectParticipantId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}',
    'OTHER-PROJECT-SENTINEL-PARTICIPANT', 'Other project participant', '${adminId}', '${adminId}'
  );
  insert into public.gamification_events (
    organization_id, project_id, actor_id, action, points, source_type, source_id
  ) values (
    '11111111-1111-4111-8111-111111111111', '${otherProjectId}', '${adminId}',
    'canonical_snapshot_sentinel', 37, 'task', '${otherProjectTaskId}'
  );
  insert into public.daily_eod_briefs (
    id, organization_id, project_id, author_id, author_role, brief_date, workflow_status,
    moved_outcome, tomorrow_priorities
  ) values (
    '${otherProjectEodId}', '11111111-1111-4111-8111-111111111111', '${otherProjectId}',
    '${adminId}', 'admin', current_date, 'draft', 'OTHER-PROJECT-SENTINEL-EOD', array['One','Two','Three']
  );
`;
