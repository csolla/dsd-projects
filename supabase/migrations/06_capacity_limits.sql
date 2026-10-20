-- =====================================================================
-- 06_capacity_limits.sql
-- Monthly Marketing capacity, time off, bank holidays, and 80% / 100%
-- limit notifications for Education and Planning Center.
-- Run once in the Supabase SQL editor, AFTER 05_resourcing.sql.
-- Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Working hours and holiday calendar per person
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists daily_hours numeric,
  add column if not exists holiday_region text;

do $$ begin
  alter table public.profiles add constraint profiles_holiday_region_check
    check (holiday_region is null or holiday_region in ('Madrid','England'));
exception when duplicate_object then null; end $$;

-- Only the admin can change capacity settings (extends the 05 trigger)
create or replace function public.protect_resourcing_profile_cols()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and not public.is_resourcing_admin()
     and (new.is_admin is distinct from old.is_admin
          or new.resourcing_bu is distinct from old.resourcing_bu
          or new.counts_in_capacity is distinct from old.counts_in_capacity
          or new.daily_hours is distinct from old.daily_hours
          or new.holiday_region is distinct from old.holiday_region) then
    raise exception 'Only the admin can change resourcing settings';
  end if;
  return new;
end $$;

-- Let the admin edit other people's capacity settings from the tool
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

-- ---------------------------------------------------------------------
-- 2. Bank holidays and time off
-- ---------------------------------------------------------------------
create table if not exists public.public_holidays (
  region text not null check (region in ('Madrid','England')),
  holiday_date date not null,
  name text not null,
  primary key (region, holiday_date)
);
alter table public.public_holidays enable row level security;
drop policy if exists public_holidays_read on public.public_holidays;
create policy public_holidays_read on public.public_holidays for select to authenticated using (true);
drop policy if exists public_holidays_write on public.public_holidays;
create policy public_holidays_write on public.public_holidays for all to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

create table if not exists public.time_off (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.profiles(id) on delete cascade,
  off_date date not null,
  note text,
  created_at timestamptz not null default now(),
  unique (person_id, off_date)
);
alter table public.time_off enable row level security;
drop policy if exists time_off_read on public.time_off;
create policy time_off_read on public.time_off for select to authenticated
  using (public.is_resourcing_admin() or person_id = auth.uid());
drop policy if exists time_off_write on public.time_off;
create policy time_off_write on public.time_off for all to authenticated
  using (public.is_resourcing_admin()) with check (public.is_resourcing_admin());

-- ---------------------------------------------------------------------
-- 3. Monthly capacity: daily hours x working days, minus bank holidays
--    and time off, minus a 20% buffer. Counted people only.
-- ---------------------------------------------------------------------
create or replace function public.resourcing_month_capacity_raw(p_month date)
returns numeric language sql stable security definer set search_path = public as $$
  with days as (
    select d::date as d
    from generate_series(date_trunc('month', p_month), date_trunc('month', p_month) + interval '1 month - 1 day', interval '1 day') d
    where extract(isodow from d) < 6
  ), ppl as (
    select id, daily_hours, holiday_region from public.profiles
    where counts_in_capacity and coalesce(daily_hours, 0) > 0
  )
  select round(coalesce(sum(ppl.daily_hours), 0) * 0.8, 1)
  from ppl cross join days
  where not exists (select 1 from public.public_holidays h where h.region = ppl.holiday_region and h.holiday_date = days.d)
    and not exists (select 1 from public.time_off t where t.person_id = ppl.id and t.off_date = days.d)
$$;
revoke execute on function public.resourcing_month_capacity_raw(date) from public, anon, authenticated;

-- What the app calls: admin and the two directors only
create or replace function public.resourcing_month_capacity(p_month date)
returns numeric language sql stable security definer set search_path = public as $$
  select case when public.is_resourcing_admin() or public.my_resourcing_bu() is not null
              then public.resourcing_month_capacity_raw(p_month) end
$$;
grant execute on function public.resourcing_month_capacity(date) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Notifications at 80% and 100% of a unit's monthly limit (admin only)
-- ---------------------------------------------------------------------
alter table public.notifications
  add column if not exists message text,
  add column if not exists business_unit text;
alter table public.notifications alter column task_id drop not null;
alter table public.notifications alter column project_id drop not null;
alter table public.notifications alter column from_id drop not null;

-- If notifications.type is limited to a fixed list, drop that limit so
-- the new 'resourcing_limit' type can be stored
do $$ declare c text; begin
  for c in select conname from pg_constraint
           where conrelid = 'public.notifications'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%type%'
  loop execute format('alter table public.notifications drop constraint %I', c); end loop;
end $$;

create table if not exists public.resourcing_alerts (
  business_unit text not null,
  month date not null,
  level int not null,
  sent_at timestamptz not null default now(),
  primary key (business_unit, month, level)
);
alter table public.resourcing_alerts enable row level security;
drop policy if exists resourcing_alerts_admin on public.resourcing_alerts;
create policy resourcing_alerts_admin on public.resourcing_alerts for select to authenticated
  using (public.is_resourcing_admin());

create or replace function public.check_resourcing_limits()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_bu text := public.bu_rollup(new.business_unit);
  v_month date := date_trunc('month', new.entry_date)::date;
  v_target numeric;
  v_cap numeric;
  v_limit numeric;
  v_used numeric;
  v_label text;
begin
  if v_bu not in ('Education', 'Planning Center') then return new; end if;
  if not exists (select 1 from public.profiles where id = new.person_id and counts_in_capacity) then return new; end if;
  v_target := case when v_bu = 'Education' then 0.7 else 0.3 end;
  v_cap := public.resourcing_month_capacity_raw(v_month);
  if v_cap is null or v_cap <= 0 then return new; end if;
  v_limit := v_cap * v_target;
  select coalesce(sum(t.hours), 0) into v_used
    from public.time_entries t join public.profiles p on p.id = t.person_id
   where p.counts_in_capacity and public.bu_rollup(t.business_unit) = v_bu
     and t.entry_date >= v_month and t.entry_date < (v_month + interval '1 month');
  v_label := trim(to_char(v_month, 'Month')) || ' ' || to_char(v_month, 'YYYY');

  if v_used >= v_limit then
    insert into public.resourcing_alerts (business_unit, month, level) values (v_bu, v_month, 100) on conflict do nothing;
    if found then
      insert into public.notifications (recipient_id, type, message, business_unit, read)
      select id, 'resourcing_limit',
             format('%s has reached its %s limit: %sh used of %sh', v_bu, v_label, round(v_used, 1), round(v_limit, 1)),
             v_bu, false
      from public.profiles where is_admin;
      -- don't send a separate 80% alert afterwards for the same month
      insert into public.resourcing_alerts (business_unit, month, level) values (v_bu, v_month, 80) on conflict do nothing;
    end if;
  elsif v_used >= v_limit * 0.8 then
    insert into public.resourcing_alerts (business_unit, month, level) values (v_bu, v_month, 80) on conflict do nothing;
    if found then
      insert into public.notifications (recipient_id, type, message, business_unit, read)
      select id, 'resourcing_limit',
             format('%s is at %s%% of its %s limit: %sh used of %sh', v_bu, round(v_used / v_limit * 100), v_label, round(v_used, 1), round(v_limit, 1)),
             v_bu, false
      from public.profiles where is_admin;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists check_resourcing_limits on public.time_entries;
create trigger check_resourcing_limits
  after insert or update of hours, entry_date, business_unit on public.time_entries
  for each row execute function public.check_resourcing_limits();

-- ---------------------------------------------------------------------
-- 5. Realtime for the new tables
-- ---------------------------------------------------------------------
do $$ begin alter publication supabase_realtime add table public.time_off;        exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.public_holidays; exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 6. Data: hours, calendars, bank holidays and the time off you gave me
-- ---------------------------------------------------------------------
update public.profiles set daily_hours = 7.5, holiday_region = 'Madrid'
  where role = 'staff' and (name ilike 'Marita%' or name ilike 'Daisy%');
update public.profiles set daily_hours = 6, holiday_region = 'England'
  where role = 'staff' and name ilike 'Steph%';

insert into public.public_holidays (region, holiday_date, name) values
  ('Madrid',  '2026-10-12', 'Fiesta Nacional de España'),
  ('Madrid',  '2026-11-02', 'Todos los Santos (moved from Sunday)'),
  ('Madrid',  '2026-11-09', 'La Almudena (Madrid city)'),
  ('Madrid',  '2026-12-07', 'Día de la Constitución (moved from Sunday)'),
  ('Madrid',  '2026-12-08', 'Inmaculada Concepción'),
  ('Madrid',  '2026-12-25', 'Navidad'),
  ('England', '2026-12-25', 'Christmas Day'),
  ('England', '2026-12-28', 'Boxing Day (substitute day)')
on conflict do nothing;

insert into public.time_off (person_id, off_date, note)
select p.id, d::date, 'Holiday'
from public.profiles p
cross join unnest(array['2026-10-01','2026-12-28','2026-12-29','2026-12-30','2026-12-31']::date[]) d
where p.role = 'staff' and p.name ilike 'Daisy%'
on conflict do nothing;

insert into public.time_off (person_id, off_date, note)
select p.id, d::date, 'Holiday'
from public.profiles p
cross join unnest(array['2026-12-21','2026-12-22','2026-12-23','2026-12-24','2026-12-29','2026-12-30','2026-12-31']::date[]) d
where p.role = 'staff' and p.name ilike 'Steph%'
on conflict do nothing;

-- Check: October should be 351.6, November 328.8, December 283.2
select to_char(m, 'Mon YYYY') as month,
       public.resourcing_month_capacity_raw(m::date) as capacity_after_buffer,
       round(public.resourcing_month_capacity_raw(m::date) * 0.7, 1) as education_limit,
       round(public.resourcing_month_capacity_raw(m::date) * 0.3, 1) as planning_center_limit
from generate_series('2026-10-01'::date, '2026-12-01'::date, interval '1 month') m;
