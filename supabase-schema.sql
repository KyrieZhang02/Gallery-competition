-- FRAME! Photo Contest submission backend
-- Run this in Supabase SQL Editor after creating your project.

create extension if not exists "pgcrypto";

create table if not exists public.photo_submissions (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    submission_type text not null default 'individual',
    name text not null,
    email text not null,
    residence_country_region text not null,
    school text not null,
    photo_1_name_description text not null,
    photo_2_name_description text,
    photo_3_name_description text,
    photo_4_name_description text,
    photo_5_name_description text,
    series_description text,
    camera text,
    rules_confirmation boolean not null default false,
    message text not null,
    files jsonb not null default '[]'::jsonb
);

alter table public.photo_submissions
add column if not exists submission_type text not null default 'individual';

alter table public.photo_submissions enable row level security;

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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'submissions',
    'submissions',
    true,
    10485760,
    array['image/jpeg', 'image/png', 'application/zip']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Allow public submission file uploads" on storage.objects;
create policy "Allow public submission file uploads"
on storage.objects
for insert
to anon
with check (bucket_id = 'submissions');

drop policy if exists "Allow public submission file reads" on storage.objects;
create policy "Allow public submission file reads"
on storage.objects
for select
to anon
using (bucket_id = 'submissions');
