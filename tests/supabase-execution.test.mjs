import assert from 'node:assert/strict';
import test from 'node:test';

import { withDisposablePostgres } from './helpers/supabase-execution-postgres.mjs';

test('authoritative task lifecycle executes independently', { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations({
      async beforeMigration(migration) {
        if (migration.endsWith('_harden_execution_boundaries.sql')) database.execute(preHardeningFixtures);
        if (migration.endsWith('_authoritative_task_lifecycle.sql')) database.execute(preTaskLifecycleFixtures);
      },
    });
    assert.ok(migrations.some((migration) => migration.endsWith('_authoritative_task_lifecycle.sql')));

    assert.equal(database.query(`
      select title = 'Preserved lifecycle fixture'
        and acceptance_criteria = 'Attach the verified evidence packet.'
        and estimated_hours = 6.50
        and created_at = '2026-08-10 09:00:00+00'::timestamptz
      from public.tasks where id = 'c1111111-1111-4111-8111-111111111111'
    `), 't');
    assert.equal(database.query(`
      select relrowsecurity from pg_class where oid = 'public.task_review_history'::regclass
    `), 't');
    assert.equal(database.query(`
      select has_table_privilege('authenticated', 'public.tasks', 'select')
        and not has_table_privilege('authenticated', 'public.tasks', 'update')
        and has_table_privilege('authenticated', 'public.task_review_history', 'select')
        and not has_table_privilege('authenticated', 'public.task_review_history', 'insert')
        and has_function_privilege('authenticated', 'public.rpc_aoi_task_detail(uuid)', 'execute')
        and has_function_privilege('authenticated', 'public.rpc_aoi_update_task_checkpoint(uuid,integer,text,text,timestamptz)', 'execute')
        and has_function_privilege('authenticated', 'public.rpc_aoi_review_task(uuid,text,text,timestamptz)', 'execute')
        and has_function_privilege('service_role', 'public.rpc_aoi_task_detail(uuid)', 'execute')
        and has_function_privilege('service_role', 'public.rpc_aoi_update_task_checkpoint(uuid,integer,text,text,timestamptz)', 'execute')
        and has_function_privilege('service_role', 'public.rpc_aoi_review_task(uuid,text,text,timestamptz)', 'execute')
        and not has_function_privilege('anon', 'public.rpc_aoi_review_task(uuid,text,text,timestamptz)', 'execute')
    `), 't');

    for (const signature of [
      'public.rpc_aoi_task_detail(uuid)',
      'public.rpc_aoi_update_task_checkpoint(uuid,integer,text,text,timestamptz)',
      'public.rpc_aoi_review_task(uuid,text,text,timestamptz)',
    ]) {
      const definition = await database.functionDefinition(signature);
      assert.match(definition, /SECURITY DEFINER/);
      assert.match(definition, /SET search_path TO ''/);
    }
    assert.equal(database.query(`
      select count(*) from pg_proc procedure
      join pg_namespace namespace on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'public'
        and procedure.proname = 'rpc_aoi_update_task_checkpoint'
        and procedure.pronargs = 4
    `), '0');

    assert.equal(database.query(`
      select exists (
        select 1 from jsonb_array_elements(public.rpc_aoi_demo_dashboard()->'tasks') task
        where task->>'id' = 'c1111111-1111-4111-8111-111111111111'
          and task->>'acceptanceCriteria' = 'Attach the verified evidence packet.'
          and task->>'estimatedHours' = '6.50'
      )
    `, authenticated('15151515-1515-4515-8515-151515151515')), 't');
    assert.equal(database.query(`
      select detail->>'acceptanceCriteria' = 'Attach the verified evidence packet.'
        and detail->>'estimatedHours' = '6.50'
        and jsonb_array_length(detail->'reviewHistory') = 0
      from (select public.rpc_aoi_task_detail('c1111111-1111-4111-8111-111111111111') detail) payload
    `, authenticated('15151515-1515-4515-8515-151515151515')), 't');

    const selfCompletion = database.execute(`
      select public.rpc_aoi_update_task_checkpoint(
        'c2222222-2222-4222-8222-222222222222', 100, 'completed', 'I completed this task.',
        '2026-08-10 10:00:00+00'::timestamptz
      );
    `, { ...authenticated('15151515-1515-4515-8515-151515151515'), allowFailure: true });
    assert.notEqual(selfCompletion.status, 0);
    assert.match(selfCompletion.stderr, /TASK_SELF_COMPLETION_FORBIDDEN/);

    const internReview = database.execute(`
      select public.rpc_aoi_review_task(
        'c3333333-3333-4333-8333-333333333333', 'approve', null,
        '2026-08-10 10:00:00+00'::timestamptz
      );
    `, { ...authenticated('15151515-1515-4515-8515-151515151515'), allowFailure: true });
    assert.notEqual(internReview.status, 0);
    assert.match(internReview.stderr, /ADMIN_REQUIRED/);

    assert.equal(database.query(`
      select public.rpc_aoi_update_task_checkpoint(
        'c1111111-1111-4111-8111-111111111111', 100, 'submitted', 'Evidence packet attached.',
        '2026-08-10 10:00:00+00'::timestamptz
      )->>'status'
    `, authenticated('15151515-1515-4515-8515-151515151515')), 'submitted');
    const staleCheckpoint = database.execute(`
      select public.rpc_aoi_update_task_checkpoint(
        'c1111111-1111-4111-8111-111111111111', 90, 'blocked', 'Stale browser tab.',
        '2026-08-10 10:00:00+00'::timestamptz
      );
    `, { ...authenticated('15151515-1515-4515-8515-151515151515'), allowFailure: true });
    assert.notEqual(staleCheckpoint.status, 0);
    assert.match(staleCheckpoint.stderr, /TASK_STALE_WRITE/);

    for (const note of ['  ', 'Fix it']) {
      const invalidRevision = database.execute(`
        select public.rpc_aoi_review_task(
          'c1111111-1111-4111-8111-111111111111', 'request_revision', '${note}',
          (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
        );
      `, { ...authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), allowFailure: true });
      assert.notEqual(invalidRevision.status, 0);
      assert.match(invalidRevision.stderr, /TASK_REVIEW_NOTE_REQUIRED/);
    }

    assert.equal(database.query(`
      select public.rpc_aoi_review_task(
        'c1111111-1111-4111-8111-111111111111', 'request_revision',
        'Replace the unverified quote and attach the signed source.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 'revision_requested');
    assert.equal(database.query(`
      select public.rpc_aoi_update_task_checkpoint(
        'c1111111-1111-4111-8111-111111111111', 100, 'resubmitted',
        'Replaced the quote and attached the signed source.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('15151515-1515-4515-8515-151515151515')), 'resubmitted');
    const mutatePendingResubmission = database.execute(`
      select public.rpc_aoi_update_task_checkpoint(
        'c1111111-1111-4111-8111-111111111111', 90, 'in_progress', 'Changing pending work.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      );
    `, { ...authenticated('15151515-1515-4515-8515-151515151515'), allowFailure: true });
    assert.notEqual(mutatePendingResubmission.status, 0);
    assert.match(mutatePendingResubmission.stderr, /TASK_CHECKPOINT_LOCKED/);
    assert.equal(database.query(`
      select public.rpc_aoi_review_task(
        'c1111111-1111-4111-8111-111111111111', 'request_revision',
        'The replacement still lacks the source signature and date.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 'revision_requested');
    assert.equal(database.query(`
      select public.rpc_aoi_update_task_checkpoint(
        'c1111111-1111-4111-8111-111111111111', 100, 'resubmitted',
        'Attached the dated source with the required signature.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('15151515-1515-4515-8515-151515151515')), 'resubmitted');
    assert.equal(database.query(`
      select public.rpc_aoi_review_task(
        'c1111111-1111-4111-8111-111111111111', 'approve', 'Verified against the signed source.',
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 'approved');
    assert.equal(database.query(`
      select public.rpc_aoi_review_task(
        'c1111111-1111-4111-8111-111111111111', 'complete', null,
        (select updated_at from public.tasks where id = 'c1111111-1111-4111-8111-111111111111')
      )->>'status'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 'completed');
    assert.equal(database.query(`
      select public.rpc_aoi_review_task(
        'c3333333-3333-4333-8333-333333333333', 'approve', null,
        '2026-08-10 10:00:00+00'::timestamptz
      )->>'status'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 'approved');

    assert.equal(database.query(`
      select string_agg(action || ':' || to_status, ',' order by created_at, id)
      from public.task_review_history
      where task_id = 'c1111111-1111-4111-8111-111111111111'
    `, authenticated('15151515-1515-4515-8515-151515151515')),
    '"request_revision:revision_requested,request_revision:revision_requested,approve:approved,complete:completed"');
    assert.equal(database.query(`
      select jsonb_array_length(detail->'reviewHistory') = 4
        and detail->>'status' = 'completed'
        and detail->>'completedBy' = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      from (select public.rpc_aoi_task_detail('c1111111-1111-4111-8111-111111111111') detail) payload
    `, authenticated('15151515-1515-4515-8515-151515151515')), 't');
    assert.equal(database.query(`
      select count(*) from public.task_review_history
      where task_id = 'c1111111-1111-4111-8111-111111111111'
    `, authenticated('77777777-7777-4777-8777-777777777777')), '0');

    const crossWorkspaceDetail = database.execute(`
      select public.rpc_aoi_task_detail('c1111111-1111-4111-8111-111111111111');
    `, { ...authenticated('77777777-7777-4777-8777-777777777777'), allowFailure: true });
    assert.notEqual(crossWorkspaceDetail.status, 0);
    assert.match(crossWorkspaceDetail.stderr, /TASK_NOT_FOUND/);

    const rewriteHistory = database.execute(`
      update public.task_review_history set note = 'rewritten'
      where task_id = 'c1111111-1111-4111-8111-111111111111';
    `, { allowFailure: true });
    assert.notEqual(rewriteHistory.status, 0);
    assert.match(rewriteHistory.stderr, /TASK_REVIEW_HISTORY_APPEND_ONLY/);
  });
});

test('fresh migrations execute in timestamp order with hardened RPC behavior', { timeout: 120_000 }, async () => {
  await withDisposablePostgres(async (database) => {
    const migrations = await database.applyMigrations({
      async beforeMigration(migration) {
        if (migration.endsWith('_harden_execution_boundaries.sql')) {
          database.execute(preHardeningFixtures);
        }
        if (migration.endsWith('_authoritative_task_lifecycle.sql')) {
          database.execute(preTaskLifecycleFixtures);
        }
      },
    });
    assert.ok(migrations.includes('20260804120125_harden_rls_event_trigger.sql'));
    assert.ok(migrations.includes('20260808010000_workflow_integrity.sql'));

    database.execute(researchEditFixtures);

    assert.equal(database.query(`
      select has_function_privilege(
        'authenticated',
        'public.rpc_aoi_update_research_record(text,uuid,jsonb,timestamptz,text)',
        'execute'
      )
    `), 't');
    assert.equal(database.query(`
      select has_table_privilege('authenticated', 'public.research_review_history', 'select')
        and not has_table_privilege('authenticated', 'public.research_review_history', 'insert')
        and not has_table_privilege('authenticated', 'public.research_review_history', 'update')
        and not has_table_privilege('authenticated', 'public.research_review_history', 'delete')
    `), 't');
    assert.equal(database.query(`
      select bool_and(
        not has_table_privilege('authenticated', format('public.%I', table_name), 'insert')
        and not has_table_privilege('authenticated', format('public.%I', table_name), 'update')
      )
      from (values ('respondents'), ('research_sessions'), ('evidence_records'),
        ('product_events'), ('value_exchange_observations'), ('pmf_observations')) tables(table_name)
    `), 't');
    assert.match(await database.functionDefinition('public.rpc_aoi_save_research_record(text,jsonb)'), /SECURITY DEFINER/);
    for (const signature of [
      'public.rpc_aoi_update_research_record(text,uuid,jsonb,timestamptz,text)',
      'public.rpc_aoi_review_research_record(text,uuid,text,text,timestamptz)',
    ]) {
      const definition = await database.functionDefinition(signature);
      assert.match(definition, /SECURITY DEFINER/);
      assert.match(definition, /SET search_path TO ''/);
    }

    const invalidCreatedEvidence = database.execute(`
      select public.rpc_aoi_save_research_record('evidence', jsonb_build_object(
        'workflowStatus', 'submitted', 'pmfLayer', 'H1', 'title', '', 'evidenceText', '',
        'sourceLink', 'https://example.test/source', 'limitations', 'Known limitation.'
      ));
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(invalidCreatedEvidence.status, 0);
    assert.match(invalidCreatedEvidence.stderr, /EVIDENCE_TITLE_REQUIRED/);
    const invalidCreatedValue = database.execute(`
      select public.rpc_aoi_save_research_record('value_exchange', jsonb_build_object(
        'workflowStatus', 'submitted', 'respondentId', 'd1111111-1111-4111-8111-111111111111',
        'segmentCode', 'families', 'hardwarePrice', ''
      ));
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(invalidCreatedValue.status, 0);
    assert.match(invalidCreatedValue.stderr, /HARDWARE_PRICE_REQUIRED/);

    const editableResearch = [
      ['respondent', 'd1111111-1111-4111-8111-111111111111', { notes: 'Edited respondent draft' }, 'public.respondents', "notes = 'Edited respondent draft'"],
      ['session', 'd2222222-2222-4222-8222-222222222222', { unmetNeed: 'Edited session draft' }, 'public.research_sessions', "unmet_need = 'Edited session draft'"],
      ['evidence', 'd3333333-3333-4333-8333-333333333333', { evidenceText: 'Edited evidence draft' }, 'public.evidence_records', "evidence_text = 'Edited evidence draft'"],
      ['product_event', 'd4444444-4444-4444-8444-444444444444', { mainFriction: 'Edited product event draft' }, 'public.product_events', "main_friction = 'Edited product event draft'"],
      ['value_exchange', 'd5555555-5555-4555-8555-555555555555', { mainObjection: 'Edited value draft' }, 'public.value_exchange_observations', "main_objection = 'Edited value draft'"],
      ['observation', 'd6666666-6666-4666-8666-666666666666', { numericValue: 4 }, 'public.pmf_observations', 'numeric_value = 4'],
    ];
    const originalUpdatedAt = new Map();
    for (const [recordType, recordId, payload, table, predicate] of editableResearch) {
      const expectedUpdatedAt = database.query(`select updated_at from ${table} where id = '${recordId}'`);
      originalUpdatedAt.set(recordId, expectedUpdatedAt);
      assert.equal(database.query(`
        select result->>'id' = '${recordId}'
          and result->>'workflowStatus' = 'draft'
        from (select public.rpc_aoi_update_research_record(
          '${recordType}', '${recordId}', ${sqlJson(payload)}, '${expectedUpdatedAt}', 'save'
        ) result) updated
      `, authenticated(researchAssignee)), 't');
      assert.equal(database.query(`
        select id = '${recordId}' and workflow_status = 'draft' and ${predicate}
        from ${table} where id = '${recordId}'
      `), 't');
    }

    const staleResearchUpdate = database.execute(`
      select public.rpc_aoi_update_research_record(
        'respondent', 'd1111111-1111-4111-8111-111111111111', '{"notes":"stale overwrite"}',
        '${originalUpdatedAt.get('d1111111-1111-4111-8111-111111111111')}', 'save'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(staleResearchUpdate.status, 0);
    assert.match(staleResearchUpdate.stderr, /RESEARCH_STALE_WRITE/);

    const currentRespondentUpdatedAt = database.query(`
      select updated_at from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'
    `);
    const unassignedResearchUpdate = database.execute(`
      select public.rpc_aoi_update_research_record(
        'respondent', 'd1111111-1111-4111-8111-111111111111', '{"notes":"unauthorized overwrite"}',
        '${currentRespondentUpdatedAt}', 'save'
      );
    `, { ...authenticated(otherResearchIntern), allowFailure: true });
    assert.notEqual(unassignedResearchUpdate.status, 0);
    assert.match(unassignedResearchUpdate.stderr, /RESEARCH_RECORD_NOT_ASSIGNED/);

    const scopeChange = database.execute(`
      select public.rpc_aoi_update_research_record(
        'respondent', 'd1111111-1111-4111-8111-111111111111',
        '{"projectId":"44444444-4444-4444-8444-444444444444"}',
        '${currentRespondentUpdatedAt}', 'save'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(scopeChange.status, 0);
    assert.match(scopeChange.stderr, /RESEARCH_SCOPE_IMMUTABLE/);

    const pendingRespondentUpdatedAt = database.query(`
      select updated_at from public.respondents where id = 'd7777777-7777-4777-8777-777777777777'
    `);
    const invalidRespondentSubmission = database.execute(`
      select public.rpc_aoi_update_research_record(
        'respondent', 'd7777777-7777-4777-8777-777777777777', '{}',
        '${pendingRespondentUpdatedAt}', 'submit'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(invalidRespondentSubmission.status, 0);
    assert.match(invalidRespondentSubmission.stderr, /CONSENT_REQUIRED/);

    const evidenceUpdatedAt = database.query(`
      select updated_at from public.evidence_records where id = 'd3333333-3333-4333-8333-333333333333'
    `);
    const invalidEvidenceSubmission = database.execute(`
      select public.rpc_aoi_update_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', '{"limitations":""}',
        '${evidenceUpdatedAt}', 'submit'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(invalidEvidenceSubmission.status, 0);
    assert.match(invalidEvidenceSubmission.stderr, /LIMITATIONS_REQUIRED/);

    assert.equal(database.query(`
      select result->>'workflowStatus' = 'submitted'
      from (select public.rpc_aoi_update_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', '{}',
        '${evidenceUpdatedAt}', 'submit'
      ) result) submitted
    `, authenticated(researchAssignee)), 't');

    const submittedEvidenceUpdatedAt = database.query(`
      select updated_at from public.evidence_records where id = 'd3333333-3333-4333-8333-333333333333'
    `);
    const submittedResearchUpdate = database.execute(`
      select public.rpc_aoi_update_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', '{"evidenceText":"locked"}',
        '${submittedEvidenceUpdatedAt}', 'save'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(submittedResearchUpdate.status, 0);
    assert.match(submittedResearchUpdate.stderr, /RESEARCH_RECORD_LOCKED/);

    const revisionWithoutNote = database.execute(`
      select public.rpc_aoi_review_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', 'request_revision', '  ',
        '${submittedEvidenceUpdatedAt}'
      );
    `, { ...authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), allowFailure: true });
    assert.notEqual(revisionWithoutNote.status, 0);
    assert.match(revisionWithoutNote.stderr, /REVIEW_REVISION_NOTE_REQUIRED/);

    assert.equal(database.query(`
      select result->>'workflowStatus' = 'revision_requested'
      from (select public.rpc_aoi_review_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', 'request_revision',
        'Clarify the source and explain the limitation.', '${submittedEvidenceUpdatedAt}'
      ) result) reviewed
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 't');
    assert.equal(database.query(`
      select count(*) = 1
        and min(from_status) = 'submitted'
        and min(to_status) = 'revision_requested'
        and min(notes) = 'Clarify the source and explain the limitation.'
      from public.research_review_history
      where record_type = 'evidence'
        and record_id = 'd3333333-3333-4333-8333-333333333333'
    `), 't');
    assert.equal(database.query(`
      select count(*)
      from public.research_review_history
      where record_type = 'evidence'
        and record_id = 'd3333333-3333-4333-8333-333333333333'
    `, authenticated(otherResearchIntern)), '0');

    const revisionUpdatedAt = database.query(`
      select updated_at from public.evidence_records where id = 'd3333333-3333-4333-8333-333333333333'
    `);
    assert.equal(database.query(`
      select result->>'id' = 'd3333333-3333-4333-8333-333333333333'
        and result->>'workflowStatus' = 'submitted'
      from (select public.rpc_aoi_update_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333',
        '{"evidenceText":"Revised evidence with clearer provenance"}',
        '${revisionUpdatedAt}', 'resubmit'
      ) result) resubmitted
    `, authenticated(researchAssignee)), 't');
    assert.equal(database.query(`
      select count(*) = 1 and min(evidence_text) = 'Revised evidence with clearer provenance'
      from public.evidence_records
      where id = 'd3333333-3333-4333-8333-333333333333' and workflow_status = 'submitted'
    `), 't');

    const staleResearchReview = database.execute(`
      select public.rpc_aoi_review_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', 'approve', 'Stale review.',
        '${submittedEvidenceUpdatedAt}'
      );
    `, { ...authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), allowFailure: true });
    assert.notEqual(staleResearchReview.status, 0);
    assert.match(staleResearchReview.stderr, /RESEARCH_STALE_WRITE/);
    const resubmittedEvidenceUpdatedAt = database.query(`
      select updated_at from public.evidence_records where id = 'd3333333-3333-4333-8333-333333333333'
    `);

    assert.equal(database.query(`
      select result->>'workflowStatus' = 'approved'
      from (select public.rpc_aoi_review_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', 'approve', 'Provenance verified.',
        '${resubmittedEvidenceUpdatedAt}'
      ) result) reviewed
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 't');
    assert.equal(database.query(`
      select count(*) = 2 and count(*) filter (where to_status = 'approved') = 1
      from public.research_review_history
      where record_type = 'evidence'
        and record_id = 'd3333333-3333-4333-8333-333333333333'
    `), 't');
    const rewriteResearchHistory = database.execute(`
      update public.research_review_history
      set notes = 'rewritten'
      where record_type = 'evidence'
        and record_id = 'd3333333-3333-4333-8333-333333333333';
    `, { allowFailure: true });
    assert.notEqual(rewriteResearchHistory.status, 0);
    assert.match(rewriteResearchHistory.stderr, /RESEARCH_REVIEW_HISTORY_APPEND_ONLY/);

    const approvedEvidenceUpdatedAt = database.query(`
      select updated_at from public.evidence_records where id = 'd3333333-3333-4333-8333-333333333333'
    `);
    const approvedResearchUpdate = database.execute(`
      select public.rpc_aoi_update_research_record(
        'evidence', 'd3333333-3333-4333-8333-333333333333', '{"evidenceText":"locked"}',
        '${approvedEvidenceUpdatedAt}', 'save'
      );
    `, { ...authenticated(researchAssignee), allowFailure: true });
    assert.notEqual(approvedResearchUpdate.status, 0);
    assert.match(approvedResearchUpdate.stderr, /RESEARCH_RECORD_LOCKED/);
    assert.ok(migrations.some((migration) => migration.endsWith('_authoritative_task_lifecycle.sql')));

    const pmf = await database.functionDefinition('public.rpc_aoi_pmf_snapshot()');
    assert.match(pmf, /respondent\.consent_status = 'granted'/);
    assert.match(pmf, /e\.respondent_id is null or exists/);

    const gate = await database.functionDefinition('private.create_aoi_gate_snapshot(text,text,text)');
    assert.match(gate, /evidence\.respondent_id is null or exists/);
    assert.match(gate, /observation\.respondent_id is null or exists/);

    const reports = await database.functionDefinition('public.rpc_aoi_daily_eod_reports(jsonb,integer,integer)');
    assert.match(reports, /brief\.project_id = v_project_id/);

    const replay = await database.functionDefinition('public.rpc_aoi_public_survey_replay(uuid,text,text,text,text)');
    assert.match(replay, /invitation\.invitation_status not in \('revoked', 'bounced'\)/);

    const dashboard = await database.functionDefinition('public.rpc_aoi_demo_dashboard()');
    assert.match(dashboard, /profile\.status = 'active'/);
    assert.match(dashboard, /not profile\.must_change_password/);
    assert.match(dashboard, /organization\.status = 'active'/);

    assert.equal(database.query(`
      select has_function_privilege('authenticated', 'private.create_aoi_gate_snapshot(text,text,text)', 'execute')
    `), 'f');
    assert.equal(database.query(`
      select has_function_privilege('authenticated', 'public.rpc_aoi_create_gate_snapshot(text,text,text)', 'execute')
    `), 't');

    assert.equal(database.query(`
      select count(*)
      from pg_proc procedure
      join pg_namespace namespace on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'public'
        and procedure.proname = 'rpc_aoi_public_survey_replay'
    `), '1');

    assert.equal(database.query(`
      select not ((public.rpc_aoi_pmf_snapshot()->'evidence') @>
        jsonb_build_array(jsonb_build_object('id', 'b2222222-2222-4222-8222-222222222222'::uuid)))
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 't');

    const passwordChangeDashboard = database.execute(
      'select public.rpc_aoi_demo_dashboard();',
      { ...authenticated('66666666-6666-4666-8666-666666666666'), allowFailure: true },
    );
    assert.notEqual(passwordChangeDashboard.status, 0);
    assert.match(passwordChangeDashboard.stderr, /WORKSPACE_ACCESS_REQUIRED/);

    const archivedDashboard = database.execute(
      'select public.rpc_aoi_demo_dashboard();',
      { ...authenticated('77777777-7777-4777-8777-777777777777'), allowFailure: true },
    );
    assert.notEqual(archivedDashboard.status, 0);
    assert.match(archivedDashboard.stderr, /WORKSPACE_ACCESS_REQUIRED/);

    const ambiguousLegacyDashboard = database.execute(`select public.rpc_aoi_demo_dashboard();`, {
      ...authenticated('55555555-5555-4555-8555-555555555555'), allowFailure: true,
    });
    assert.notEqual(ambiguousLegacyDashboard.status, 0);
    assert.match(ambiguousLegacyDashboard.stderr, /WORKSPACE_ACCESS_REQUIRED|PROJECT_SELECTION_REQUIRED/);
    assert.equal(database.query(`
      select public.rpc_aoi_select_project('44444444-4444-4444-8444-444444444444')->>'selectedProjectId'
    `, authenticated('55555555-5555-4555-8555-555555555555')), '44444444-4444-4444-8444-444444444444');
    assert.equal(database.query(`
      select
        dashboard.payload->'organization'->>'id' = '33333333-3333-4333-8333-333333333333'
        and dashboard.payload->'project'->>'id' = '44444444-4444-4444-8444-444444444444'
      from (select public.rpc_aoi_demo_dashboard() payload) dashboard
    `, authenticated('55555555-5555-4555-8555-555555555555')), 't');

    const revokedReplay = database.execute(`
      select public.rpc_aoi_public_survey_replay(
        'a5555555-5555-4555-8555-555555555555',
        'resume-secret',
        'replay-key',
        'link-secret',
        'invite-secret'
      );
    `, { ...serviceRole(), allowFailure: true });
    assert.notEqual(revokedReplay.status, 0);
    assert.match(revokedReplay.stderr, /SURVEY_RESPONSE_UNAVAILABLE/);

    assert.equal(database.query(`
      select answer_value = '"secret@example.com"'::jsonb
        and display_snapshot = '{"raw":"secret@example.com"}'::jsonb
      from public.survey_answers where id = 'a6666666-6666-4666-8666-666666666666'
    `), 't');
    assert.equal(database.query(`
      select answer_value = '"secret@example.com"'::jsonb
      from public.survey_response_identifiers where id = 'a7777777-7777-4777-8777-777777777777'
    `), 't');
    assert.equal(database.query(`
      select previous_value = '"old-secret@example.com"'::jsonb
        and new_value = '"secret@example.com"'::jsonb
      from public.survey_answer_revisions where id = 'a8888888-8888-4888-8888-888888888888'
    `), 't');
    assert.equal(database.query(`
      select count(*) from public.survey_response_identifiers
      where id = 'a7777777-7777-4777-8777-777777777777'
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), '0');

    assert.equal(database.query(`
      select has_function_privilege('authenticated', 'public.rpc_accept_invitation()', 'execute')
    `), 'f');
    const directInvitationAcceptance = database.execute(
      'select public.rpc_accept_invitation();',
      { ...authenticated('12121212-1212-4212-8212-121212121212'), allowFailure: true },
    );
    assert.notEqual(directInvitationAcceptance.status, 0);

    database.execute(`
      update public.survey_response_identifiers
      set is_active = true, answer_value = '"future-secret@example.com"'::jsonb
      where id = 'a7777777-7777-4777-8777-777777777777';
      update public.survey_response_identifiers
      set is_active = false
      where id = 'a7777777-7777-4777-8777-777777777777';
      update public.survey_answers
      set is_active = true,
          answer_value = '"future-secret@example.com"'::jsonb,
          display_snapshot = '{"raw":"future-secret@example.com"}'::jsonb
      where id = 'a6666666-6666-4666-8666-666666666666';
      update public.survey_answer_revisions
      set previous_value = '"old-future-secret@example.com"'::jsonb,
          new_value = '"future-secret@example.com"'::jsonb
      where id = 'a8888888-8888-4888-8888-888888888888';
    `);
    assert.equal(database.query(`
      select not identifier.is_active
        and identifier.answer_value = 'null'::jsonb
        and not answer.is_active
        and answer.answer_value = 'null'::jsonb
        and answer.display_snapshot = '{}'::jsonb
        and revision.previous_value = 'null'::jsonb
        and revision.new_value = 'null'::jsonb
      from public.survey_response_identifiers identifier
      join public.survey_answers answer on answer.submission_id = identifier.submission_id
        and answer.question_id = identifier.question_id
      join public.survey_answer_revisions revision on revision.answer_id = answer.id
      where identifier.id = 'a7777777-7777-4777-8777-777777777777'
    `), 't');

    assert.equal(database.query(`
      select (public.rpc_aoi_create_gate_snapshot('H1', 'insufficient', 'Consent-safe execution test') ->> 'id') is not null
    `, authenticated('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), 't');

  });
});

function authenticated(actor) {
  return { actor, role: 'authenticated' };
}

function serviceRole() {
  return { role: 'service_role' };
}

function sqlJson(value) {
  return `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;
}

const researchAssignee = '13131313-1313-4313-8313-131313131313';
const otherResearchIntern = '14141414-1414-4414-8414-141414141414';

const researchEditFixtures = `
  insert into auth.users (id, email_confirmed_at) values
    ('${researchAssignee}', now()),
    ('${otherResearchIntern}', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password) values
    ('${researchAssignee}', 'Research Assignee', 'research-assignee', 'active', false),
    ('${otherResearchIntern}', 'Other Research Intern', 'other-research-intern', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status, joined_at) values
    ('11111111-1111-4111-8111-111111111111', '${researchAssignee}', 'intern', 'active', '2026-01-01'),
    ('11111111-1111-4111-8111-111111111111', '${otherResearchIntern}', 'intern', 'active', '2026-01-01');

  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by, notes
  ) values
    (
      'd1111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222', 'EDITABLE-RESEARCH',
      (select id from public.research_segments where project_id = '22222222-2222-4222-8222-222222222222' and code = 'families'),
      'Consumer', 'granted', 'active', 'draft', '${researchAssignee}', '${researchAssignee}', 'Original respondent draft'
    ),
    (
      'd7777777-7777-4777-8777-777777777777',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222', 'PENDING-CONSENT',
      (select id from public.research_segments where project_id = '22222222-2222-4222-8222-222222222222' and code = 'families'),
      'Consumer', 'pending', 'recruiting', 'draft', '${researchAssignee}', '${researchAssignee}', 'Cannot submit yet'
    );
  insert into public.research_sessions (
    id, organization_id, project_id, respondent_id, segment_id, pmf_layer, method,
    session_date, unmet_need, workflow_status, assigned_to, created_by
  ) values (
    'd2222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
    'd1111111-1111-4111-8111-111111111111',
    (select segment_id from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'),
    'H1', 'Interview', '2026-08-12', 'Original unmet need', 'draft', '${researchAssignee}', '${researchAssignee}'
  );
  insert into public.evidence_records (
    id, organization_id, project_id, respondent_id, session_id, segment_id, pmf_layer,
    dimension, type, evidence_type, stance, strength, title, evidence_text,
    consent_status, source_link, limitations, workflow_status, assigned_to, recorded_by
  ) values (
    'd3333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
    'd1111111-1111-4111-8111-111111111111', 'd2222222-2222-4222-8222-222222222222',
    (select segment_id from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'),
    'H1', 'Need', 'Interview', 'Interview', 'supporting', 3, 'Editable evidence',
    'Original evidence draft', 'granted', 'https://example.com/source', 'Small synthetic sample',
    'draft', '${researchAssignee}', '${researchAssignee}'
  );
  insert into public.product_events (
    id, organization_id, project_id, respondent_id, segment_id, event_date, study_week,
    main_friction, workflow_status, assigned_to, created_by
  ) values (
    'd4444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
    'd1111111-1111-4111-8111-111111111111',
    (select segment_id from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'),
    '2026-08-12', 1, 'Original product friction', 'draft', '${researchAssignee}', '${researchAssignee}'
  );
  insert into public.value_exchange_observations (
    id, organization_id, project_id, respondent_id, segment_id, observed_at,
    main_objection, workflow_status, assigned_to, created_by
  ) values (
    'd5555555-5555-4555-8555-555555555555',
    '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
    'd1111111-1111-4111-8111-111111111111',
    (select segment_id from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'),
    '2026-08-12', 'Original value objection', 'draft', '${researchAssignee}', '${researchAssignee}'
  );
  insert into public.pmf_observations (
    id, organization_id, project_id, definition_id, respondent_id, session_id, segment_id,
    numeric_value, source_link, workflow_status, assigned_to, created_by
  ) values (
    'd6666666-6666-4666-8666-666666666666',
    '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
    (select id from public.pmf_metric_definitions where project_id = '22222222-2222-4222-8222-222222222222' and code = 'change_events_per_user'),
    'd1111111-1111-4111-8111-111111111111', 'd2222222-2222-4222-8222-222222222222',
    (select segment_id from public.respondents where id = 'd1111111-1111-4111-8111-111111111111'),
    2, 'https://example.com/metric-source', 'draft', '${researchAssignee}', '${researchAssignee}'
  );
`;

const preHardeningFixtures = `
  insert into public.organizations (id, slug, name, status)
  values
    ('33333333-3333-4333-8333-333333333333', 'secondary-active', 'Secondary active', 'active'),
    ('88888888-8888-4888-8888-888888888888', 'archived-workspace', 'Archived workspace', 'archived');
  insert into public.projects (id, organization_id, code, name, status, created_at)
  values
    ('44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333', 'SECONDARY', 'Secondary project', 'active', '2026-08-01'),
    ('99999999-9999-4999-8999-999999999999', '88888888-8888-4888-8888-888888888888', 'ARCHIVED', 'Archived project', 'active', '2026-08-01');

  insert into auth.users (id, email_confirmed_at) values
    ('55555555-5555-4555-8555-555555555555', now()),
    ('66666666-6666-4666-8666-666666666666', now()),
    ('77777777-7777-4777-8777-777777777777', now()),
    ('12121212-1212-4212-8212-121212121212', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password) values
    ('55555555-5555-4555-8555-555555555555', 'Multi Workspace', 'multi-workspace', 'active', false),
    ('66666666-6666-4666-8666-666666666666', 'Password Change', 'password-change', 'password_change_required', true),
    ('77777777-7777-4777-8777-777777777777', 'Archived Workspace User', 'archived-workspace-user', 'active', false),
    ('12121212-1212-4212-8212-121212121212', 'Invited User', 'invited-user', 'invited', true);
  insert into public.organization_memberships (organization_id, user_id, role, status, joined_at) values
    ('11111111-1111-4111-8111-111111111111', '55555555-5555-4555-8555-555555555555', 'intern', 'active', '2026-01-01'),
    ('33333333-3333-4333-8333-333333333333', '55555555-5555-4555-8555-555555555555', 'admin', 'active', '2026-02-01'),
    ('11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', 'intern', 'password_change_required', '2026-01-01'),
    ('88888888-8888-4888-8888-888888888888', '77777777-7777-4777-8777-777777777777', 'admin', 'active', '2026-01-01'),
    ('11111111-1111-4111-8111-111111111111', '12121212-1212-4212-8212-121212121212', 'intern', 'invited', '2026-03-01');

  insert into public.respondents (
    id, organization_id, project_id, external_id, segment_id, respondent_type,
    consent_status, status, workflow_status, assigned_to, created_by
  ) values (
    'b1111111-1111-4111-8111-111111111111',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'WITHDRAWN-TEST',
    (select id from public.research_segments where project_id = '22222222-2222-4222-8222-222222222222' order by sequence, id limit 1),
    'Consumer', 'withdrawn', 'active', 'approved',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );
  insert into public.evidence_records (
    id, organization_id, project_id, respondent_id, segment_id, type, stance,
    strength, title, consent_status, recorded_by, pmf_layer, dimension,
    evidence_text, workflow_status, assigned_to
  ) values (
    'b2222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'b1111111-1111-4111-8111-111111111111',
    (select id from public.research_segments where project_id = '22222222-2222-4222-8222-222222222222' order by sequence, id limit 1),
    'interview', 'supporting', 3, 'Withdrawn raw evidence', 'granted',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'H1', 'need',
    'Must not be returned after consent withdrawal', 'approved',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );

  insert into public.survey_assets (
    id, organization_id, project_id, title, lifecycle_status, owner_id, assigned_to, created_by
  ) values (
    'a1111111-1111-4111-8111-111111111111',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '{"en":"Execution test","zh":"Execution test"}', 'published',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );
  insert into public.survey_versions (
    id, organization_id, project_id, asset_id, version_number, version_status,
    definition, definition_hash, submitted_by, published_at
  )
  select
    'a2222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a1111111-1111-4111-8111-111111111111', 1, 'published', definition,
    extensions.digest(definition::text, 'sha256'),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now()
  from (values ('{"blocks":[{"blocks":[{"id":"email","type":"email","privacy":{"classification":"direct_identifier"}}]}]}'::jsonb)) fixture(definition);
  insert into public.survey_links (
    id, organization_id, project_id, asset_id, version_id, token_hash,
    link_mode, identity_mode, link_status, created_by
  ) values (
    'a3333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a1111111-1111-4111-8111-111111111111',
    'a2222222-2222-4222-8222-222222222222',
    extensions.digest('link-secret', 'sha256'), 'invited', 'identified', 'active',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );
  insert into public.survey_invitations (
    id, organization_id, project_id, link_id, token_hash, invitation_status, created_by
  ) values (
    'a4444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a3333333-3333-4333-8333-333333333333',
    extensions.digest('invite-secret', 'sha256'), 'revoked',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );
  insert into public.survey_submissions (
    id, organization_id, project_id, asset_id, version_id, link_id, invitation_id,
    resume_token_hash, response_status, idempotency_key, submitted_at
  ) values (
    'a5555555-5555-4555-8555-555555555555',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a1111111-1111-4111-8111-111111111111',
    'a2222222-2222-4222-8222-222222222222',
    'a3333333-3333-4333-8333-333333333333',
    'a4444444-4444-4444-8444-444444444444',
    extensions.digest('resume-secret', 'sha256'), 'submitted', 'replay-key', now()
  );
  insert into public.survey_answers (
    id, organization_id, project_id, submission_id, question_id, answer_value,
    display_snapshot, is_active
  ) values (
    'a6666666-6666-4666-8666-666666666666',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a5555555-5555-4555-8555-555555555555', 'email',
    '"secret@example.com"', '{"raw":"secret@example.com"}', false
  );
  insert into public.survey_response_identifiers (
    id, organization_id, project_id, submission_id, question_id, answer_value, is_active
  ) values (
    'a7777777-7777-4777-8777-777777777777',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a5555555-5555-4555-8555-555555555555', 'email', '"secret@example.com"', false
  );
  insert into public.survey_answer_revisions (
    id, organization_id, project_id, answer_id, revision, previous_value, new_value, change_reason
  ) values (
    'a8888888-8888-4888-8888-888888888888',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'a6666666-6666-4666-8666-666666666666', 2,
    '"old-secret@example.com"', '"secret@example.com"', 'Legacy identifier revision'
  );
`;

const preTaskLifecycleFixtures = `
  insert into auth.users (id, email_confirmed_at)
  values ('15151515-1515-4515-8515-151515151515', now());
  insert into public.profiles (id, display_name, login_identifier, status, must_change_password)
  values ('15151515-1515-4515-8515-151515151515', 'Lifecycle Intern', 'lifecycle-intern', 'active', false);
  insert into public.organization_memberships (organization_id, user_id, role, status, joined_at)
  values (
    '11111111-1111-4111-8111-111111111111',
    '15151515-1515-4515-8515-151515151515',
    'intern', 'active', '2026-08-01'
  );

  insert into public.tasks (
    id, organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, due_date, pmf_layer, progress, points,
    assigned_to, created_by, acceptance_criteria, estimated_hours, created_at, updated_at
  ) values
    (
      'c1111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'Preserved lifecycle fixture', 'Submit a verified evidence packet.', 'in_progress', 'high',
      'Lifecycle Intern', 'LI', '2026-08-15', 'H1', 75, 180,
      '15151515-1515-4515-8515-151515151515', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'Attach the verified evidence packet.', 6.50, '2026-08-10 09:00:00+00', '2026-08-10 10:00:00+00'
    ),
    (
      'c2222222-2222-4222-8222-222222222222',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'Self completion denial fixture', 'Remain subject to administrator completion.', 'in_progress', 'medium',
      'Lifecycle Intern', 'LI', '2026-08-16', 'H2', 90, 120,
      '15151515-1515-4515-8515-151515151515', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'Administrator completes approved work.', 2.00, '2026-08-10 09:00:00+00', '2026-08-10 10:00:00+00'
    ),
    (
      'c3333333-3333-4333-8333-333333333333',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'Direct approval fixture', 'Prove submitted work can be approved directly.', 'submitted', 'medium',
      'Lifecycle Intern', 'LI', '2026-08-17', 'H3', 100, 100,
      '15151515-1515-4515-8515-151515151515', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'Approve the submitted result.', 1.50, '2026-08-10 09:00:00+00', '2026-08-10 10:00:00+00'
    );
`;
