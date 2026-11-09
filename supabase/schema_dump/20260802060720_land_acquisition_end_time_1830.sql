-- Office day ends at 18:30. Land Acquisition was created with 18:00, which was
-- my assumption from mirroring the housekeeping row's shape rather than a
-- stated requirement. They start at 09:00 and finish at 18:30 like everyone
-- else, so their working day is 9.5 hours, not 9.
update office_timings
   set check_out_time = '18:30',
       working_hours  = '9.5'
 where name = 'Land Acquisition Hours';

select name, check_in_time, check_out_time, grace_minutes, working_hours, no_fixed_timing
from office_timings order by name;
