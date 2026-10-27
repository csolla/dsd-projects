-- Loads the new Education requests (Oct 2026) into Atlas as approved projects with tasks.
-- Source: https://claude.ai/artifact/F2eLqby4hqkq4ikRqJnKXX . Hours are the midpoint of each estimate.
-- People are matched by email. Run once: it stops if any of these projects already exists.

create or replace function pg_temp.add_task(p_project uuid, p_title text, p_desc text, p_assignee uuid, p_due date, p_hours numeric, p_bu text)
returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.tasks (title, description, status, assignee_id, due_date, estimated_hours, business_unit)
  values (p_title, coalesce(p_desc, ''), 'todo', p_assignee, p_due, coalesce(p_hours, 0), p_bu) returning id into v_id;
  insert into public.task_projects (task_id, project_id) values (v_id, p_project);
  return v_id;
end $$;

create or replace function pg_temp.add_sub(p_task uuid, p_title text, p_assignee uuid, p_hours numeric, p_pos int)
returns void language sql as $$
  insert into public.subtasks (task_id, title, assignee_id, estimated_hours, position, done)
  values (p_task, p_title, p_assignee, p_hours, p_pos, false);
$$;

do $$
declare
  marita uuid := (select id from public.profiles where email ilike 'mmacdonald@digitalsmiledesign.com');
  daisy  uuid := (select id from public.profiles where email ilike 'dmason%@digitalsmiledesign.com');
  steph  uuid := (select id from public.profiles where email ilike 'swrennall@digitalsmiledesign.com');
  carlota uuid := (select id from public.profiles where email ilike 'csolla@digitalsmiledesign.com');
  page text := 'Analysis, brief check and questions: https://claude.ai/artifact/F2eLqby4hqkq4ikRqJnKXX';
  p uuid; t uuid;
begin
  if marita is null or daisy is null or steph is null or carlota is null then
    raise exception 'Could not find everyone by email (Marita %, Daisy %, Steph %, Carlota %). Nothing was added.', marita, daisy, steph, carlota;
  end if;
  if exists (select 1 from public.projects where name in (
      'Smile Rehabilitation & Occlusion course (Calamita & Coachman)', 'DSD Workshops Series',
      'III DSD Clinics Getaway Houston 2027', 'DSD Online migration: user communications')) then
    raise exception 'At least one of these projects already exists. Nothing was added.';
  end if;

  -- 1. Smile Rehabilitation & Occlusion (Education)
  insert into public.projects (name, team, status, start_date, end_date, business_unit, planned_hours, is_unplanned, request_details)
  values ('Smile Rehabilitation & Occlusion course (Calamita & Coachman)', 'Education', 'planning', '2026-11-30', '2026-12-18', 'Education', 57.5, false,
    'Request from Carlos (Asana form). Logo, landing page, order page, Craft and DSD Online setup for the course on 11–13 Nov 2027 at DSD Madrid HQ. Design depends on the Education rebrand. ' || page)
  returning id into p;
  perform pg_temp.add_task(p, 'Kick-off and clarifications with Carlos', null, steph, '2026-12-01', 1, 'Education');
  perform pg_temp.add_task(p, 'Logo: 2–3 ideas, revisions, final files (APA/Kois style)', 'Needs the new Institute brand.', steph, '2026-12-04', 11, 'Education');
  perform pg_temp.add_task(p, 'Landing page copy and SEO', null, steph, '2026-12-04', 4, 'Education');
  perform pg_temp.add_task(p, 'Landing page design, desktop and mobile', 'Needs the new Institute brand.', steph, '2026-12-11', 11, 'Education');
  perform pg_temp.add_task(p, 'Gather images: faculty portraits, clinical cases, venue', null, steph, '2026-12-11', 3, 'Education');
  perform pg_temp.add_task(p, 'Build in Craft: curriculum, faculty, FAQ, form', null, steph, '2026-12-17', 11, 'Education');
  perform pg_temp.add_task(p, 'Order page: EUR and USD, early bird and standard prices', null, steph, '2026-12-17', 6.5, 'Education');
  perform pg_temp.add_task(p, 'DSD Online setup: product, prices, early bird', 'Old or new DSD Online platform? See the migration project.', null, '2026-12-17', 4.5, 'Education');
  perform pg_temp.add_task(p, 'Test purchase, review rounds, go-live', null, null, '2026-12-18', 5.5, 'Education');

  -- 2. DSD Workshops Series (Education)
  insert into public.projects (name, team, status, start_date, end_date, business_unit, planned_hours, is_unplanned, request_details)
  values ('DSD Workshops Series', 'Education', 'planning', '2026-11-30', '2027-01-22', 'Education', 82.5, false,
    'Request from Carlos (Asana form). One landing page for five courses, in person (21–22 May and 24–25 Sep 2027) and on demand (from 21 Apr 2027). Sales setup tasks have no date until sales opening is agreed. ' || page)
  returning id into p;
  perform pg_temp.add_task(p, 'Kick-off with Carlos; collect the five course documents', null, carlota, '2026-12-04', 1, 'Education');
  perform pg_temp.add_task(p, 'Interviews with Christian and Angelo', 'Prepare questions, run 2 sessions, write up.', steph, '2026-12-04', 7, 'Education');
  perform pg_temp.add_task(p, 'Page copy: series intro, 5 courses, 10 cards, faculty, schedule, booking FAQ, SEO', null, steph, '2026-12-18', 13.5, 'Education');
  perform pg_temp.add_task(p, 'Visual direction for the series and imagery for 5 courses', 'Needs the new Institute brand.', steph, '2026-12-18', 7, 'Education');
  perform pg_temp.add_task(p, 'Page design based on the Designing Smiles layout', 'Needs the new Institute brand.', steph, '2027-01-15', 11, 'Education');
  perform pg_temp.add_task(p, 'Build in Craft: course sections, 10 cards, schedule, faculty, FAQ', null, steph, '2027-01-20', 13.5, 'Education');
  perform pg_temp.add_task(p, 'Review rounds with Carlos and faculty, QA, go-live', null, steph, '2027-01-22', 5.5, 'Education');
  perform pg_temp.add_task(p, 'Order pages: 5 in person and 5 on demand', 'Due date once sales opening is agreed.', steph, null, 13.5, 'Education');
  perform pg_temp.add_task(p, 'DSD Online: 5 on-demand products, plus access for in-person buyers', 'Due date once sales opening is agreed.', null, null, 7, 'Education');
  perform pg_temp.add_task(p, 'Test purchases: both formats, both dates, instalments, discounts', 'Due date once sales opening is agreed.', null, null, 3.5, 'Education');

  -- 3. Getaway Houston (Shared, PC owns; 70/30 until the split is agreed)
  insert into public.projects (name, team, status, start_date, end_date, business_unit, planned_hours, budget_education, budget_pc, is_unplanned, request_details)
  values ('III DSD Clinics Getaway Houston 2027', 'Shared', 'planning', '2026-11-30', '2027-03-14', 'Shared', 92, 64.4, 27.6, false,
    'Request from Carlos, owned by Planning Center (JJ). Event 11–14 Mar 2027, Houston. Budgets use the 70/30 rule until the split is agreed at the kick-off. Physical items to production by 5 Feb 2027. ' || page)
  returning id into p;
  t := pg_temp.add_task(p, 'Kick-off: prepare, run, write up next steps', 'Proposed Tue 1 Dec, 16:00 Madrid / 10:00 Miami.', null, '2026-12-01', 0, 'Shared');
  perform pg_temp.add_sub(t, 'Kick-off (Marita)', marita, 2.75, 0);
  perform pg_temp.add_sub(t, 'Kick-off (Carlota)', carlota, 2.75, 1);
  perform pg_temp.add_task(p, 'Event look and feel for the third edition (key visual)', null, marita, '2026-12-11', 7, 'Shared');
  perform pg_temp.add_task(p, 'Official digital invitation: copy, design, email build', 'Send before the Christmas break.', marita, '2026-12-18', 7, 'Shared');
  perform pg_temp.add_task(p, 'Programme communication with hotel booking link', null, marita, '2027-01-29', 7, 'Shared');
  perform pg_temp.add_task(p, 'Session names and descriptions', null, marita, '2027-01-29', 5, 'Shared');
  perform pg_temp.add_task(p, 'Awards: categories with DC and JJ, certificates, trophy design', 'To production by 5 Feb.', marita, '2027-02-05', 11.5, 'Shared');
  perform pg_temp.add_task(p, 'Welcome letter and goodie bag contents', 'To production by 5 Feb.', marita, '2027-02-05', 8, 'Shared');
  perform pg_temp.add_task(p, 'Participation certificate or commemorative pin', 'To production by 5 Feb.', marita, '2027-02-05', 5, 'Shared');
  perform pg_temp.add_task(p, 'Extra materials: signage, sponsor logos, course guide', null, marita, '2027-02-05', 12.5, 'Shared');
  perform pg_temp.add_task(p, 'Black & White Gala invitation and dress code', null, marita, '2027-02-19', 4.5, 'Shared');
  perform pg_temp.add_task(p, 'Countdown communications (about 5 messages)', 'Starts in January; last one before the event.', marita, '2027-02-26', 13.5, 'Shared');
  perform pg_temp.add_task(p, 'Badge layout and merge with the participants list', 'Final list by 1 Mar.', marita, '2027-03-01', 5.5, 'Shared');

  -- 4. DSD Online migration (Education). Dates are placeholders until the migration dates are set.
  insert into public.projects (name, team, status, start_date, end_date, business_unit, planned_hours, is_unplanned, request_details)
  values ('DSD Online migration: user communications', 'Education', 'planning', '2026-12-01', '2026-12-31', 'Education', 39, false,
    'Moving current DSD Online users to the new platform. Education runs the migration and support; Marketing makes the assets. Dates are placeholders in December until the migration dates are agreed. ' || page)
  returning id into p;
  t := pg_temp.add_task(p, 'Communication plan with Education: groups, messages, dates', 'After the planning meeting on Thu 3 Dec.', null, '2026-12-04', 0, 'Education');
  perform pg_temp.add_sub(t, 'Communication plan (Carlota)', carlota, 1.6, 0);
  perform pg_temp.add_sub(t, 'Communication plan (Steph)', steph, 1.7, 1);
  perform pg_temp.add_sub(t, 'Communication plan (Daisy)', daisy, 1.7, 2);
  perform pg_temp.add_task(p, 'Email sequence (about 6–8 emails)', 'Placeholder date.', steph, '2026-12-18', 12, 'Education');
  perform pg_temp.add_task(p, 'FAQ and help articles for the support team', 'Placeholder date.', steph, '2026-12-18', 6, 'Education');
  perform pg_temp.add_task(p, 'Step-by-step PDF on how to get into the new platform', 'Placeholder date.', steph, '2026-12-18', 6, 'Education');
  perform pg_temp.add_task(p, 'Banners: old platform, website, social posts', 'Placeholder date.', null, '2026-12-18', 6.5, 'Education');
  t := pg_temp.add_task(p, 'Reviews and changes after Education''s feedback', 'Placeholder date.', null, '2026-12-18', 0, 'Education');
  perform pg_temp.add_sub(t, 'Reviews (Steph)', steph, 1.75, 0);
  perform pg_temp.add_sub(t, 'Reviews (designer)', null, 1.75, 1);
end $$;

-- Check: one row per project with its task count and hours
select pr.name, count(distinct tp.task_id) as tasks,
       coalesce(sum(distinct_t.estimated_hours), 0) + coalesce((select sum(s.estimated_hours) from public.subtasks s join public.task_projects x on x.task_id = s.task_id where x.project_id = pr.id), 0) as hours
from public.projects pr
join public.task_projects tp on tp.project_id = pr.id
join public.tasks distinct_t on distinct_t.id = tp.task_id and distinct_t.status <> 'operational'
where pr.name in ('Smile Rehabilitation & Occlusion course (Calamita & Coachman)', 'DSD Workshops Series', 'III DSD Clinics Getaway Houston 2027', 'DSD Online migration: user communications')
group by pr.id, pr.name order by pr.name;
