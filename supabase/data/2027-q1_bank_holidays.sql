-- Bank holidays January–March 2027, so capacity for Q1 2027 is right.
-- Madrid: regional calendar approved for 2027 (check against the BOCM decree when published). Madrid city's local days fall outside Q1.
-- England: England and Wales bank holidays (check against gov.uk/bank-holidays).
insert into public.public_holidays (region, holiday_date, name)
select v.region, v.holiday_date::date, v.name
from (values
  ('Madrid',  '2027-01-01', 'Año Nuevo'),
  ('Madrid',  '2027-01-06', 'Epifanía del Señor'),
  ('Madrid',  '2027-03-19', 'San José'),
  ('Madrid',  '2027-03-25', 'Jueves Santo'),
  ('Madrid',  '2027-03-26', 'Viernes Santo'),
  ('England', '2027-01-01', 'New Year''s Day'),
  ('England', '2027-03-26', 'Good Friday'),
  ('England', '2027-03-29', 'Easter Monday')
) as v(region, holiday_date, name)
where not exists (select 1 from public.public_holidays h where h.region = v.region and h.holiday_date = v.holiday_date::date);

select region, holiday_date, name from public.public_holidays
where holiday_date between '2027-01-01' and '2027-03-31' order by holiday_date, region;
