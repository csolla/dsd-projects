-- Read-only check: the 10 most recent Resourcing to-dos and which meeting they belong to
select
  to_char(i.created_at at time zone 'Europe/Madrid', 'DD Mon HH24:MI') as added,
  m.business_unit,
  m.scheduled_for as meeting_date,
  i.kind,
  i.text,
  i.done
from public.resourcing_items i
join public.resourcing_meetings m on m.id = i.meeting_id
order by i.created_at desc
limit 10;
