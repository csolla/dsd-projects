-- =====================================================================
-- 15_departments.sql
-- Every DSD team becomes a department in Atlas.
-- Departments: Planning Center, Delight, Education, Corporate, Marketing.
-- Projects get a Department (which team owns the project), alongside
-- the Business unit they already have. People keep using profiles.team
-- as their department, now with Delight allowed again.
-- Run once in the Supabase SQL editor, AFTER 14_shared_meetings_tasks.sql.
-- =====================================================================

-- 1. Projects get a Department
alter table public.projects add column if not exists department text;

alter table public.projects drop constraint if exists projects_department_check;
alter table public.projects add constraint projects_department_check
  check (department is null or department in ('Planning Center', 'Delight', 'Education', 'Corporate', 'Marketing'));

-- 2. Every project already in Atlas is Marketing work
update public.projects set department = 'Marketing' where department is null;

-- 3. People's department: allow the five departments (old values are left as they are)
do $$ declare c text; begin
  for c in select conname from pg_constraint
           where conrelid = 'public.profiles'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%team%'
  loop execute format('alter table public.profiles drop constraint %I', c); end loop;
end $$;
alter table public.profiles add constraint profiles_team_department_check
  check (team is null or team = '' or team in ('Planning Center', 'Delight', 'Education', 'Corporate', 'Marketing')) not valid;

-- 4. Check: how many projects per department, and who has which department
select department, count(*) as projects from public.projects group by department order by department;
select coalesce(nullif(team, ''), '(none)') as department, count(*) as people from public.profiles where role = 'staff' group by 1 order by 1;
