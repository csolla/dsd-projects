-- =====================================================================
-- 05_resourcing.sql
-- Marketing resourcing: business unit on projects, planned hours,
-- unplanned requests, time logging, BU meeting records, flags for Brendon.
-- Run once in the Supabase SQL editor (project yxevnyyzezfdsbclhvvp).
-- Safe to re-run: every statement is idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Profiles: who is admin, who is a BU director, whose hours count
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_admin boolean not null default false,
  add column if not exists resourcing_bu text,
  add column if not exists counts_in_capacity boolean not null default false;

do $$ begin
  alter table public.profiles add constraint profiles_resourcing_bu_check
    check (resourcing_bu is null or resourcing_bu in ('Education','Planning Center'));
exception when duplicate_object then null; end $$;

create or replace function public.is_resourcing_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.my_resourcing_bu()
returns text language sql stable security definer set search_path = public as $$
  select resourcing_bu from public.profiles where id = auth.uid()
$$;

-- Delight is reported as part of Planning Center
create or replace function public.bu_rollup(bu text)
returns text language sql immutable as $$
  select case when bu = 'Delight' then 'Planning Center' else bu end
$$;

-- Nobody but the admin can change these three columns from the app
create or replace function public.protect_resourcing_profile_cols()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and not public.is_resourcing_admin()
     and (new.is_admin is distinct from old.is_admin
          or new.resourcing_bu is distinct from old.resourcing_bu
          or new.counts_in_capacity is distinct from old.counts_in_capacity) then
    raise exception 'Only the admin can change resourcing roles';
  end if;
  return new;
end $$;

drop trigger if exists protect_resourcing_profile_cols on public.profiles;
create trigger protect_resourcing_profile_cols
  before update on public.profiles
  for each row execute function public.protect_resourcing_profile_cols();

-- ---------------------------------------------------------------------
-- 2. Projects: business unit, plan, unplanned requests
-- ---------------------------------------------------------------------
alter table public.projects
  add column if not exists business_unit text,
  add column if not exists planned_hours numeric,
  add column if not exists priority int,
  add column if not exists is_unplanned boolean not null default false,
  add column if not exists unplanned_status text,
  add column if not exists requested_on date,
  add column if not exists swapped_for uuid references public.projects(id) on delete set null;

do $$ begin
  alter table public.projects add constraint projects_business_unit_check
    check (business_unit is null or business_unit in ('Education','Planning Center','Delight','Corporate'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.projects add constraint projects_planned_hours_check
    check (planned_hours is null or planned_hours >= 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.projects add constraint projects_unplanned_status_check
    check (unplanned_status is null or unplanned_status in ('logged','urgent_swap','accepted','declined'));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 3. Time entries
-- ---------------------------------------------------------------------
create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.profiles(id) on delete cascade,
  entry_date date not null,
  hours numeric not null check (hours > 0 and hours <= 24),
  business_unit text not null check (business_unit in ('Education','Planning Center','Delight','Corporate')),
  project_id uuid references public.projects(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  label text,              -- "Project / task" text from the workbook, or a free note
  notes text,
  source text not null default 'tool' check (source in ('tool','import')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists time_entries_date_idx on public.time_entries (entry_date);
create index if not exists time_entries_project_idx on public.time_entries (project_id);
create index if not exists time_entries_person_idx on public.time_entries (person_id);

alter table public.time_entries enable row level security;

drop policy if exists time_entries_select on public.time_entries;
create policy time_entries_select on public.time_entries for select to authenticated using (
  person_id = auth.uid()
  or public.is_resourcing_admin()
  or (
    public.bu_rollup(business_unit) = public.my_resourcing_bu()
    and exists (select 1 from public.profiles p where p.id = time_entries.person_id and p.counts_in_capacity)
  )
);

drop policy if exists time_entries_insert on public.time_entries;
create policy time_entries_insert on public.time_entries for insert to authenticated with check (
  (person_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'staff'))
  or public.is_resourcing_admin()
);

drop policy if exists time_entries_update on public.time_entries;
create policy time_entries_update on public.time_entries for update to authenticated
  using (person_id = auth.uid() or public.is_resourcing_admin())
  with check (person_id = auth.uid() or public.is_resourcing_admin());

drop policy if exists time_entries_delete on public.time_entries;
create policy time_entries_delete on public.time_entries for delete to authenticated
  using (person_id = auth.uid() or public.is_resourcing_admin());

-- Hours per business unit for a period, counting only capacity people.
-- Admin gets every BU; a director gets their own BU plus the Marketing total.
create or replace function public.resourcing_totals(p_start date, p_end date)
returns table (bucket text, hours numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v_admin boolean := public.is_resourcing_admin();
  v_bu text := public.my_resourcing_bu();
begin
  if not v_admin and v_bu is null then return; end if;
  return query
    with e as (
      select public.bu_rollup(t.business_unit) as bu, t.hours
      from public.time_entries t
      join public.profiles p on p.id = t.person_id
      where p.counts_in_capacity and t.entry_date between p_start and p_end
    )
    select e.bu, sum(e.hours)::numeric from e where v_admin or e.bu = v_bu group by e.bu
    union all
    select 'Total', coalesce(sum(e.hours), 0)::numeric from e;
end $$;
grant execute on function public.resourcing_totals(date, date) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Meeting records, decisions and actions
-- ---------------------------------------------------------------------
create table if not exists public.resourcing_meetings (
  id uuid primary key default gen_random_uuid(),
  business_unit text not null check (business_unit in ('Education','Planning Center')),
  scheduled_for date not null,
  held_on date,
  notes text not null default '',
  updated_at timestamptz not null default now(),
  unique (business_unit, scheduled_for)
);
alter table public.resourcing_meetings enable row level security;

drop policy if exists resourcing_meetings_select on public.resourcing_meetings;
create policy resourcing_meetings_select on public.resourcing_meetings for select to authenticated
  using (public.is_resourcing_admin() or business_unit = public.my_resourcing_bu());
drop policy if exists resourcing_meetings_write on public.resourcing_meetings;
create policy resourcing_meetings_write on public.resourcing_meetings for all to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

create table if not exists public.resourcing_items (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.resourcing_meetings(id) on delete cascade,
  kind text not null check (kind in ('decision','action')),
  text text not null,
  owner text,
  due_date date,
  done boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.resourcing_items enable row level security;

drop policy if exists resourcing_items_select on public.resourcing_items;
create policy resourcing_items_select on public.resourcing_items for select to authenticated using (
  public.is_resourcing_admin()
  or exists (select 1 from public.resourcing_meetings m
             where m.id = resourcing_items.meeting_id and m.business_unit = public.my_resourcing_bu())
);
drop policy if exists resourcing_items_write on public.resourcing_items;
create policy resourcing_items_write on public.resourcing_items for all to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

-- ---------------------------------------------------------------------
-- 5. Flags for Brendon (admin only, never visible to directors)
-- ---------------------------------------------------------------------
create table if not exists public.resourcing_flags (
  id uuid primary key default gen_random_uuid(),
  business_unit text not null check (business_unit in ('Education','Planning Center','Corporate')),
  meeting_id uuid references public.resourcing_meetings(id) on delete set null,
  text text not null,
  status text not null default 'open' check (status in ('open','raised','resolved')),
  outcome text,
  created_at timestamptz not null default now()
);
alter table public.resourcing_flags enable row level security;

drop policy if exists resourcing_flags_admin on public.resourcing_flags;
create policy resourcing_flags_admin on public.resourcing_flags for all to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

-- ---------------------------------------------------------------------
-- 6. Realtime
-- ---------------------------------------------------------------------
do $$ begin alter publication supabase_realtime add table public.time_entries;        exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.resourcing_meetings; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.resourcing_items;    exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.resourcing_flags;    exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 7. Roles. Each person must have signed in to the tool at least once
--    so their profile row exists. Replace the two director emails.
-- ---------------------------------------------------------------------
update public.profiles set is_admin = true
  where email = 'csolla@digitalsmiledesign.com';

update public.profiles set resourcing_bu = 'Education'
  where email = 'CARLOS_EMAIL@digitalsmiledesign.com';        -- Carlos

update public.profiles set resourcing_bu = 'Planning Center'
  where email = 'JJ_EMAIL@digitalsmiledesign.com';            -- JJ

-- The 70/30 split counts Marita, Daisy and Steph only
update public.profiles set counts_in_capacity = true
  where role = 'staff' and (name ilike 'Marita%' or name ilike 'Daisy%' or name ilike 'Steph%');

-- Check the result: you should see 1 admin, 2 directors, 3 counted people
select name, email, is_admin, resourcing_bu, counts_in_capacity
from public.profiles
where is_admin or resourcing_bu is not null or counts_in_capacity
order by name;
