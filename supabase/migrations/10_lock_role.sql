-- 10_lock_role.sql
-- Security fixes, 20 October 2026:
-- 1. Only the admin can change a person's role (stops a client making themselves staff)
-- 2. project_progress follows the same access rules as the tables behind it
-- 3. Only staff can see the people list (a client sees just their own profile)

-- 1. Add role to the columns only the admin can change (extends the 06 trigger)
create or replace function public.protect_resourcing_profile_cols()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and not public.is_resourcing_admin()
     and (new.role is distinct from old.role
          or new.is_admin is distinct from old.is_admin
          or new.resourcing_bu is distinct from old.resourcing_bu
          or new.counts_in_capacity is distinct from old.counts_in_capacity
          or new.daily_hours is distinct from old.daily_hours
          or new.holiday_region is distinct from old.holiday_region) then
    raise exception 'Only the admin can change roles and resourcing settings';
  end if;
  return new;
end $$;

-- 2. Make the view respect row level security
alter view public.project_progress set (security_invoker = true);

-- 3. Profiles: staff see everyone, anyone else sees only themselves.
--    security definer so the check doesn't loop back through this policy.
create or replace function public.i_am_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'staff' from public.profiles where id = auth.uid()), false)
$$;

drop policy if exists "profiles viewable by signed-in users" on public.profiles;
drop policy if exists "profiles viewable by staff or self" on public.profiles;
create policy "profiles viewable by staff or self" on public.profiles for select
  using (id = auth.uid() or public.i_am_staff());

-- Check: both columns should say true
select
  pg_get_functiondef('public.protect_resourcing_profile_cols'::regproc) like '%new.role%' as role_locked,
  exists (select 1 from pg_policies where tablename = 'profiles' and policyname = 'profiles viewable by staff or self') as staff_list_private;
