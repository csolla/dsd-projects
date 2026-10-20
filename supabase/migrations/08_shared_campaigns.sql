-- =====================================================================
-- 08_shared_campaigns.sql
-- Campaigns that serve Education and Planning Center at the same time
-- (e.g. Black Friday): one project, tasks tagged by business unit,
-- shared hours split 70/30 when logged, an hour budget per unit.
-- Run once in the Supabase SQL editor, AFTER 07_work_requests.sql.
-- Safe to re-run.
-- =====================================================================

-- Projects can be "Shared" and hold a budget per unit
alter table public.projects drop constraint if exists projects_business_unit_check;
alter table public.projects add constraint projects_business_unit_check
  check (business_unit is null or business_unit in ('Education','Planning Center','Delight','Corporate','Shared'));
alter table public.projects
  add column if not exists budget_education numeric,
  add column if not exists budget_pc numeric;

-- Tasks carry their own business unit tag
alter table public.tasks add column if not exists business_unit text;
do $$ begin
  alter table public.tasks add constraint tasks_business_unit_check
    check (business_unit is null or business_unit in ('Education','Planning Center','Delight','Corporate','Shared'));
exception when duplicate_object then null; end $$;

-- The two halves of a shared entry are linked so they show and delete as one
alter table public.time_entries add column if not exists split_group uuid;
create index if not exists time_entries_split_group_idx on public.time_entries (split_group);
