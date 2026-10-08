-- Tiruan minimal lingkungan Supabase supaya supabase/setup.sql bisa dijalankan
-- dan diuji di Postgres biasa (lihat supabase/tests/run.sh). Hanya memuat yang
-- dipakai setup.sql: role, auth.uid(), auth.users, storage.*, dan publikasi
-- realtime. BUKAN untuk dijalankan di project Supabase sungguhan.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email varchar(255)
);

-- Sama seperti Supabase: uid dibaca dari klaim JWT permintaan.
create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid default auth.uid()
);
alter table storage.objects enable row level security;

create function storage.foldername(name text) returns text[]
language plpgsql immutable
as $$
declare parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1:array_length(parts, 1) - 1];
end
$$;

create function storage.filename(name text) returns text
language plpgsql immutable
as $$
declare parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[array_length(parts, 1)];
end
$$;

create publication supabase_realtime;

-- Bawaan Supabase: tabel baru di schema public langsung terbuka untuk semua
-- role API. Itu sebabnya setup.sql harus mencabut hak secara eksplisit.
grant usage on schema public, auth, storage to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;
grant execute on all functions in schema storage to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
