-- Phase 5: keep survey analysis population metrics and definitions immutable.

create or replace function public.rpc_aoi_survey_analysis(p_asset_id uuid, p_population text default 'approved')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_asset public.survey_assets;
  v_allowed text[];
  v_started integer;
  v_completed integer;
  v_population_count integer;
begin
  select * into v_asset
  from public.survey_assets asset
  where asset.id = p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id)
    and auth.uid() is distinct from v_asset.owner_id
    and auth.uid() is distinct from v_asset.assigned_to then
    raise exception 'SURVEY_ASSIGNMENT_REQUIRED';
  end if;
  if p_population not in ('approved', 'operational') then raise exception 'SURVEY_POPULATION_INVALID'; end if;

  v_allowed := case when p_population = 'approved'
    then array['approved']
    else array['submitted', 'in_review', 'approved', 'revision_requested', 'rejected', 'excluded']
  end;

  select count(*) filter (where response.response_status = any(v_allowed)),
    count(*) filter (where response.submitted_at is not null and response.response_status = any(v_allowed))
  into v_started, v_completed
  from public.survey_submissions response
  where response.asset_id = p_asset_id;

  v_population_count := v_started;
  return jsonb_build_object(
    'population', p_population,
    'populationCount', v_population_count,
    'starts', v_started,
    'completed', v_completed,
    'completionRate', case when v_started = 0 then 0 else round(v_completed::numeric / v_started * 100) end,
    'statusCounts', coalesce((select jsonb_object_agg(response_status, total) from (
      select response_status, count(*) total
      from public.survey_submissions response
      where response.asset_id = p_asset_id and response.response_status = any(v_allowed)
      group by response_status
    ) status), '{}'::jsonb),
    'questions', coalesce((select jsonb_agg(summary) from (
      select jsonb_build_object(
        'versionId', response.version_id,
        'questionId', answer.question_id,
        'questionType', question#>>'{type}',
        'definition', question,
        'count', count(*),
        'denominator', v_population_count,
        'values', jsonb_agg(answer.answer_value)
      ) summary
      from public.survey_answers answer
      join public.survey_submissions response on response.id = answer.submission_id
      join public.survey_versions version on version.id = response.version_id
      cross join lateral jsonb_array_elements(version.definition->'blocks') section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
      where response.asset_id = p_asset_id
        and response.response_status = any(v_allowed)
        and answer.is_active
        and question->>'id' = answer.question_id
        and question#>>'{privacy,classification}' is distinct from 'direct_identifier'
      group by response.version_id, answer.question_id, question
    ) typed), '[]'::jsonb),
    'qualityFlags', coalesce((select jsonb_agg(jsonb_build_object('submissionId', response.id, 'flags', response.quality_flags))
      from public.survey_submissions response
      where response.asset_id = p_asset_id
        and response.response_status = any(v_allowed)
        and jsonb_array_length(response.quality_flags) > 0), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_survey_analysis(uuid, text) from public, anon;
grant execute on function public.rpc_aoi_survey_analysis(uuid, text) to authenticated;
