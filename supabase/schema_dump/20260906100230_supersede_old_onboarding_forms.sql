-- 19 forms for 15 people. Deepak has a denied submission sitting beside his
-- approved one; SOWNDARYA has two sent-back attempts under a different
-- spelling. HR has to work out which row is current every time they open the
-- list, and a stale one can be actioned by mistake.
alter table onboarding_forms
  add column if not exists superseded boolean not null default false;
alter table onboarding_forms
  add column if not exists superseded_by uuid;

comment on column onboarding_forms.superseded is
  'An older submission from the same person that a later one replaced. Hidden from the default list; nothing is deleted.';

-- Marks every earlier submission from the same person as superseded by their
-- latest. Deliberately does not delete: a denied or sent-back form is the
-- record of why, and SOWNDARYA''s spelling variants are how her name was
-- actually entered at the time.
with ranked as (
  select id, lower(trim(name)) as key, submitted_at,
         first_value(id) over (
           partition by lower(trim(name)) order by submitted_at desc
         ) as latest_id,
         row_number() over (
           partition by lower(trim(name)) order by submitted_at desc
         ) as rn
    from onboarding_forms
)
update onboarding_forms o
   set superseded = true,
       superseded_by = r.latest_id
  from ranked r
 where o.id = r.id and r.rn > 1;

-- What HR should see: one row per person, the current one.
create or replace view v_onboarding_current as
  select * from onboarding_forms where not superseded;

select count(*) filter (where superseded) as marked_superseded,
       count(*) filter (where not superseded) as current_forms
  from onboarding_forms;
