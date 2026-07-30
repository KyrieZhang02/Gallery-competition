-- FRAME! Photo Contest submission backend
-- Run this in Supabase SQL Editor after creating your project.

create extension if not exists "pgcrypto";

grant usage on schema public to anon;

create table if not exists public.photo_submissions (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    submission_type text not null default 'individual',
    name text not null,
    email text not null,
    phone text,
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

alter table public.photo_submissions
add column if not exists phone text;

alter table public.photo_submissions enable row level security;

grant insert on public.photo_submissions to anon;

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
    209715200,
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

create table if not exists public.gallery_photos (
    id uuid primary key default gen_random_uuid(),
    submission_id uuid not null references public.photo_submissions(id) on delete cascade,
    created_at timestamptz not null default now(),
    submission_type text not null,
    title text not null default '',
    artist text not null default '',
    url text not null,
    series_key text,
    series_photos jsonb
);

alter table public.gallery_photos
add column if not exists submission_id uuid references public.photo_submissions(id) on delete cascade;

alter table public.gallery_photos
add column if not exists created_at timestamptz not null default now();

alter table public.gallery_photos
add column if not exists submission_type text not null default 'individual';

alter table public.gallery_photos
add column if not exists title text not null default '';

alter table public.gallery_photos
add column if not exists artist text not null default '';

alter table public.gallery_photos
add column if not exists url text not null default '';

alter table public.gallery_photos
add column if not exists series_key text;

alter table public.gallery_photos
add column if not exists series_photos jsonb;

alter table public.gallery_photos enable row level security;

grant select on public.gallery_photos to anon;

drop policy if exists "Allow public gallery reads" on public.gallery_photos;
create policy "Allow public gallery reads"
on public.gallery_photos
for select
to anon
using (url <> '');

create or replace function public.sync_submission_to_gallery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    image_files jsonb;
    first_image jsonb;
begin
    delete from public.gallery_photos
    where submission_id = new.id;

    if new.submission_type = 'series' then
        select jsonb_agg(jsonb_build_object('url', file_item->>'url') order by file_item->>'path')
        into image_files
        from jsonb_array_elements(new.files) as file_item
        where file_item->>'type' in ('image/jpeg', 'image/png')
            and coalesce(file_item->>'url', '') <> '';

        if image_files is not null and jsonb_array_length(image_files) > 0 then
            first_image := image_files->0;

            insert into public.gallery_photos (
                submission_id,
                created_at,
                submission_type,
                title,
                artist,
                url,
                series_key,
                series_photos
            )
            values (
                new.id,
                new.created_at,
                new.submission_type,
                coalesce(nullif(trim(new.series_description), ''), 'Series submission'),
                coalesce(nullif(trim(new.name), ''), 'FRAME! Participant'),
                first_image->>'url',
                new.id::text,
                image_files
            );
        end if;
    else
        insert into public.gallery_photos (
            submission_id,
            created_at,
            submission_type,
            title,
            artist,
            url
        )
        select
            new.id,
            new.created_at,
            new.submission_type,
            coalesce(
                nullif(trim(
                    case file_item->>'field'
                        when 'photo_1' then new.photo_1_name_description
                        when 'photo_2' then new.photo_2_name_description
                        when 'photo_3' then new.photo_3_name_description
                        when 'photo_4' then new.photo_4_name_description
                        when 'photo_5' then new.photo_5_name_description
                        else ''
                    end
                ), ''),
                file_item->>'name',
                'Untitled'
            ),
            coalesce(nullif(trim(new.name), ''), 'FRAME! Participant'),
            file_item->>'url'
        from jsonb_array_elements(new.files) as file_item
        where file_item->>'field' in ('photo_1', 'photo_2', 'photo_3', 'photo_4', 'photo_5')
            and file_item->>'type' in ('image/jpeg', 'image/png')
            and coalesce(file_item->>'url', '') <> '';
    end if;

    return new;
end;
$$;

drop trigger if exists "Sync submission photos to gallery" on public.photo_submissions;
create trigger "Sync submission photos to gallery"
after insert or update of files, name, submission_type, photo_1_name_description, photo_2_name_description, photo_3_name_description, photo_4_name_description, photo_5_name_description, series_description
on public.photo_submissions
for each row
execute function public.sync_submission_to_gallery();

-- Backfill already received submissions into the public gallery table.
update public.photo_submissions
set files = files;
