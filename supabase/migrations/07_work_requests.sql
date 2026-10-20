-- =====================================================================
-- 07_work_requests.sql
-- Lets Carlos and JJ request work from Marketing inside the tool.
-- Each request becomes an unplanned request for their business unit
-- and sends the admin a notification.
-- Run once in the Supabase SQL editor, AFTER 06_capacity_limits.sql.
-- Safe to re-run.
-- =====================================================================

alter table public.projects
  add column if not exists requested_by uuid references public.profiles(id) on delete set null,
  add column if not exists request_details text,
  add column if not exists request_deadline date,
  add column if not exists request_urgent boolean not null default false;

create or replace function public.notify_work_request()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  if new.is_unplanned and new.requested_by is not null
     and not exists (select 1 from public.profiles where id = new.requested_by and is_admin) then
    select coalesce(name, email, 'Someone') into v_name from public.profiles where id = new.requested_by;
    insert into public.notifications (recipient_id, from_id, type, message, business_unit, project_id, read)
    select id, new.requested_by, 'work_request',
           format('%s requested "%s"%s%s', v_name, new.name,
                  case when new.request_deadline is not null then ', needed by ' || to_char(new.request_deadline, 'DD Mon') else '' end,
                  case when new.request_urgent then ' (urgent)' else '' end),
           public.bu_rollup(new.business_unit), new.id, false
    from public.profiles where is_admin;
  end if;
  return new;
end $$;

drop trigger if exists notify_work_request on public.projects;
create trigger notify_work_request
  after insert on public.projects
  for each row execute function public.notify_work_request();
