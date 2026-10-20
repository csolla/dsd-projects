-- =====================================================================
-- 09_unify_business_units.sql
-- One list everywhere: Education, Planning Center, Corporate
-- (plus "Shared" for campaigns that serve Education and Planning Center).
-- Delight becomes Planning Center. Projects have a single Business unit
-- field; the old Team column is kept in sync with it.
-- Marketing stays only as a department for people.
-- Run once in the Supabase SQL editor, AFTER 08_shared_campaigns.sql.
-- =====================================================================

-- 1. Delight becomes Planning Center everywhere
update public.profiles     set team = 'Planning Center'          where team = 'Delight';
update public.projects     set business_unit = 'Planning Center' where business_unit = 'Delight';
update public.tasks        set business_unit = 'Planning Center' where business_unit = 'Delight';
update public.time_entries set business_unit = 'Planning Center' where business_unit = 'Delight';

-- 2. Projects with no business unit take it from their old team, where that team is a business unit
update public.projects
   set business_unit = case team when 'Delight' then 'Planning Center' else team end
 where business_unit is null and team in ('Education', 'Planning Center', 'Delight', 'Corporate');

-- 3. Let the old Team column follow the business unit
do $$ declare c text; begin
  for c in select conname from pg_constraint
           where conrelid = 'public.projects'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%team%'
  loop execute format('alter table public.projects drop constraint %I', c); end loop;
end $$;
update public.projects set team = business_unit where business_unit is not null;

-- 4. Only the unified options are allowed from now on
alter table public.projects drop constraint if exists projects_business_unit_check;
alter table public.projects add constraint projects_business_unit_check
  check (business_unit is null or business_unit in ('Education', 'Planning Center', 'Corporate', 'Shared'));

alter table public.tasks drop constraint if exists tasks_business_unit_check;
alter table public.tasks add constraint tasks_business_unit_check
  check (business_unit is null or business_unit in ('Education', 'Planning Center', 'Corporate', 'Shared'));

alter table public.time_entries drop constraint if exists time_entries_business_unit_check;
alter table public.time_entries add constraint time_entries_business_unit_check
  check (business_unit in ('Education', 'Planning Center', 'Corporate'));

-- 5. Projects that still need a business unit (set these in Project settings)
select name, team as old_team
from public.projects
where business_unit is null
order by name;
