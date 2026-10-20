-- 11_remove_client_project_access.sql
-- Client projects were retired in October 2026, so clients no longer see any
-- project, even one marked share_with_client. Staff access is unchanged.
-- The sharing data (share_with_client, project_clients) is kept, so this can
-- be restored by recreating the policy if client sharing ever returns.

drop policy if exists "clients view shared projects" on public.projects;

-- Check: should say true
select not exists (
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'projects' and policyname = 'clients view shared projects'
) as client_access_removed;
