-- 14_shared_meetings_tasks.sql
-- Shared projects get two Meetings tasks in the Operational column: one for
-- Education and one for Planning Center. Other projects keep one, with the
-- project's business unit. Changing a project's business unit adjusts them.

create or replace function public.sync_meetings_tasks(p_project uuid, p_bu text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_units text[] := case when p_bu = 'Shared' then array['Education', 'Planning Center'] else array[p_bu] end;
  v_missing text[];
  v_task record;
  v_new uuid;
  u text;
begin
  -- Units that don't have a Meetings task yet
  select coalesce(array_agg(x), '{}') into v_missing
    from unnest(v_units) as x
   where not exists (
     select 1 from public.task_projects tp join public.tasks t on t.id = tp.task_id
      where tp.project_id = p_project and t.title = 'Meetings' and t.status = 'operational'
        and t.business_unit is not distinct from x);

  -- Meetings tasks for a unit that's no longer wanted: reuse them for a missing
  -- unit, otherwise remove them if nobody has used them (no comments, subtasks,
  -- files or hours)
  for v_task in
    select t.id from public.task_projects tp join public.tasks t on t.id = tp.task_id
     where tp.project_id = p_project and t.title = 'Meetings' and t.status = 'operational'
       and not exists (select 1 from unnest(v_units) as x where t.business_unit is not distinct from x)
     order by t.created_at
  loop
    if cardinality(v_missing) > 0 then
      update public.tasks set business_unit = v_missing[1] where id = v_task.id;
      v_missing := v_missing[2:];
    elsif not exists (select 1 from public.task_activity a where a.task_id = v_task.id and a.kind = 'comment')
      and not exists (select 1 from public.subtasks s where s.task_id = v_task.id)
      and not exists (select 1 from public.attachments f where f.task_id = v_task.id)
      and not exists (select 1 from public.time_entries e where e.task_id = v_task.id) then
      delete from public.tasks where id = v_task.id;
    end if;
  end loop;

  -- Create the ones still missing
  foreach u in array v_missing loop
    insert into public.tasks (title, description, status, business_unit)
    values ('Meetings', '', 'operational', u) returning id into v_new;
    insert into public.task_projects (task_id, project_id) values (v_new, p_project);
  end loop;
end $$;
revoke execute on function public.sync_meetings_tasks(uuid, text) from public, anon, authenticated;

-- New projects
create or replace function public.project_meetings_task()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.sync_meetings_tasks(new.id, new.business_unit);
  return new;
end $$;

-- Business unit changed
create or replace function public.project_meetings_task_bu()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.sync_meetings_tasks(new.id, new.business_unit);
  return new;
end $$;

drop function if exists public.add_meetings_task(uuid, text);

-- Existing Shared projects: add the second task
select public.sync_meetings_tasks(p.id, p.business_unit)
  from public.projects p where p.business_unit = 'Shared';

-- Check: each Shared project should show 2 (Education, Planning Center)
select p.name, count(t.id) as meetings_tasks,
       string_agg(t.business_unit, ', ' order by t.business_unit) as units
  from public.projects p
  left join public.task_projects tp on tp.project_id = p.id
  left join public.tasks t on t.id = tp.task_id and t.title = 'Meetings' and t.status = 'operational'
 where p.business_unit = 'Shared'
 group by p.name order by p.name;
