-- 12_dsd_emails_only.sql
-- Only @digitalsmiledesign.com emails can create an account. Any other email
-- is refused before the account exists, so no sign-in link is sent.
-- People who already have an account can still sign in (see the check below).

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is null or new.email not ilike '%@digitalsmiledesign.com' then
    raise exception 'Only @digitalsmiledesign.com emails can sign in';
  end if;

  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    'staff'
  );
  return new;
end;
$$;

-- Check: the first column should say true. The second lists any existing
-- accounts that aren't DSD emails (empty means there are none).
select
  pg_get_functiondef('public.handle_new_user'::regproc) like '%Only @digitalsmiledesign.com%' as dsd_only,
  (select string_agg(email || ' (' || role || ')', ', ' order by email)
     from public.profiles where email not ilike '%@digitalsmiledesign.com') as existing_non_dsd_accounts;
