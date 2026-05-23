-- Run this once if you already created the Supabase backend before series submissions were optional.

alter table public.photo_submissions
add column if not exists submission_type text not null default 'individual';

drop policy if exists "Allow public contest submissions" on public.photo_submissions;
create policy "Allow public contest submissions"
on public.photo_submissions
for insert
to anon
with check (
    rules_confirmation = true
    and name <> ''
    and email <> ''
    and residence_country_region <> ''
    and school <> ''
    and message <> ''
    and submission_type in ('individual', 'series')
    and (
        (submission_type = 'individual' and photo_1_name_description <> '')
        or
        (submission_type = 'series' and series_description <> '')
    )
);
