-- 13_operational_column.sql
-- Adds an "Operational" column to every project board, for ongoing work such
-- as meetings. Every project gets a "Meetings" task there automatically, with
-- no assignee or due date, and the project's business unit.

-- 1. Allow the new status
alter table public.tasks drop constraint if exists tasks_status_check;
alter table public.tasks add constraint tasks_status_check
  check (status in ('todo', 'doing', 'review', 'done', 'operational'));

-- 2. Progress ignores Operational tasks (they're never "finished")
create or replace view public.project_progress as
  select tp.project_id,
    count(*) filter (where t.status = 'done') as done_count,
    count(*) as total_count,
    case when count(*) = 0 then 0::numeric
      else round(100.0 * count(*) filter (where t.status = 'done') / count(*))
    end as progress_percent
  from public.task_projects tp
  join public.tasks t on t.id = tp.task_id
  where t.status <> 'operational'
  group by tp.project_id;
alter view public.project_progress set (security_invoker = true);

-- 3. Add the Meetings task to a project
create or replace function public.add_meetings_task(p_project uuid, p_bu text)
returns void language plpgsql security definer set search_path = public as $$
declare v_task uuid;
begin
  insert into public.tasks (title, description, status, business_unit)
  values ('Meetings', '', 'operational', p_bu)
  returning id into v_task;
  insert into public.task_projects (task_id, project_id) values (v_task, p_project);
end $$;
revoke execute on function public.add_meetings_task(uuid, text) from public, anon, authenticated;

-- 4. New projects get it automatically
create or replace function public.project_meetings_task()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.add_meetings_task(new.id, new.business_unit);
  return new;
end $$;
drop trigger if exists project_meetings_task on public.projects;
create trigger project_meetings_task
  after insert on public.projects
  for each row execute function public.project_meetings_task();

-- 5. If a project's business unit changes, its Meetings task follows
create or replace function public.project_meetings_task_bu()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.tasks t set business_unit = new.business_unit
    from public.task_projects tp
   where tp.task_id = t.id and tp.project_id = new.id
     and t.title = 'Meetings' and t.status = 'operational';
  return new;
end $$;
drop trigger if exists project_meetings_task_bu on public.projects;
create trigger project_meetings_task_bu
  after update of business_unit on public.projects
  for each row when (old.business_unit is distinct from new.business_unit)
  execute function public.project_meetings_task_bu();

-- 6. Existing projects: add it where it's missing
select public.add_meetings_task(p.id, p.business_unit)
  from public.projects p
 where not exists (
   select 1 from public.task_projects tp join public.tasks t on t.id = tp.task_id
    where tp.project_id = p.id and t.title = 'Meetings' and t.status = 'operational');

-- Check: both numbers should match (projects, and projects with a Meetings task)
select
  (select count(*) from public.projects) as projects,
  (select count(distinct tp.project_id) from public.task_projects tp join public.tasks t on t.id = tp.task_id
    where t.title = 'Meetings' and t.status = 'operational') as with_meetings_task;
