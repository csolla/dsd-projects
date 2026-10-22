-- Read-only check: how tasks are set up (changes nothing)
select 'tasks column' as what, column_name || ' ' || data_type || coalesce(' (' || udt_name || ')', '') || ' default ' || coalesce(column_default, '-') || ' null=' || is_nullable as detail
  from information_schema.columns where table_schema = 'public' and table_name = 'tasks'
union all
select 'task_projects column', column_name || ' ' || data_type
  from information_schema.columns where table_schema = 'public' and table_name = 'task_projects'
union all
select 'rule on tasks', conname || ': ' || pg_get_constraintdef(oid)
  from pg_constraint where conrelid = 'public.tasks'::regclass and contype = 'c'
union all
select 'trigger on ' || event_object_table, trigger_name || ' ' || action_timing || ' ' || event_manipulation
  from information_schema.triggers where event_object_schema = 'public' and event_object_table in ('tasks', 'projects', 'task_projects')
union all
select 'progress view', pg_get_viewdef('public.project_progress'::regclass);
