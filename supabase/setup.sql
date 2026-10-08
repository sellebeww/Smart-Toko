-- Setup Supabase untuk SmartToko.
--
-- Jalankan seluruh isi file ini di Supabase Dashboard > SQL Editor. Aman
-- dijalankan ulang, termasuk di atas project yang memakai versi skrip lama:
-- policy dan fungsi lama dibuang lalu dibuat ulang.
--
-- Prinsip keamanannya:
-- - Klien hanya boleh mengubah kolom yang memang miliknya (nama, kategori,
--   alamat toko). Status verifikasi hanya bisa berubah lewat fungsi di bawah,
--   yang memeriksa siapa pemanggilnya.
-- - Admin adalah baris di tabel `admins`, bukan sekadar orang yang login.
--   Tambahkan admin pertama secara manual (lihat bagian paling bawah).
-- - Semua fungsi SECURITY DEFINER memakai `search_path` tetap dan hanya bisa
--   dipanggil pengguna yang login.

-- =============================================================
-- 1. Admin
-- =============================================================
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- RLS tanpa policy = tidak bisa dibaca/ditulis klien sama sekali. Cek status
-- admin hanya lewat is_admin().
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- =============================================================
-- 2. Tabel `stores`
-- =============================================================
create table if not exists public.stores (
  id uuid primary key,
  owner_uid uuid not null references auth.users (id) on delete cascade,
  name text not null,
  category text not null,
  address text not null default '',
  created_at timestamptz not null default now(),
  verification_status text not null default 'unverified',
  rejection_reason text,
  verification_submitted_at timestamptz,
  verification_reviewed_at timestamptz,
  identity_consent_version text,
  identity_consent_at timestamptz
);

alter table public.stores
  drop constraint if exists stores_verification_status_check;
alter table public.stores
  add constraint stores_verification_status_check
  check (verification_status in ('unverified', 'pending', 'verified', 'rejected'));

alter table public.stores drop constraint if exists stores_name_check;
alter table public.stores
  add constraint stores_name_check
  check (char_length(trim(name)) between 1 and 100);

alter table public.stores drop constraint if exists stores_address_check;
alter table public.stores
  add constraint stores_address_check check (char_length(address) <= 300);

create index if not exists stores_owner_uid_idx on public.stores (owner_uid);
create index if not exists stores_verification_status_idx
  on public.stores (verification_status);

-- Realtime dipakai daftar toko di aplikasi (`.stream()`).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'stores'
  ) then
    alter publication supabase_realtime add table public.stores;
  end if;
end $$;

-- Hak kolom: klien hanya boleh mengisi/mengubah data profil toko. Kolom
-- status verifikasi dan persetujuan identitas tidak bisa disentuh langsung,
-- jadi pemilik tidak bisa menandai tokonya sendiri "verified".
revoke insert, update, delete on public.stores from anon, authenticated;
revoke select on public.stores from anon;
grant select on public.stores to authenticated;
grant insert (id, owner_uid, name, category, address)
  on public.stores to authenticated;
grant update (name, category, address) on public.stores to authenticated;

alter table public.stores enable row level security;

-- Policy versi lama.
drop policy if exists "stores_select_any_authenticated" on public.stores;

drop policy if exists "stores_select_own_or_admin" on public.stores;
create policy "stores_select_own_or_admin"
  on public.stores for select
  to authenticated
  using (owner_uid = auth.uid() or public.is_admin());

drop policy if exists "stores_insert_own" on public.stores;
create policy "stores_insert_own"
  on public.stores for insert
  to authenticated
  with check (owner_uid = auth.uid());

drop policy if exists "stores_update_own" on public.stores;
create policy "stores_update_own"
  on public.stores for update
  to authenticated
  using (owner_uid = auth.uid())
  with check (owner_uid = auth.uid());

-- Tidak ada policy delete: toko hanya ikut terhapus bersama akunnya.

-- =============================================================
-- 3. Riwayat keputusan verifikasi (audit)
-- =============================================================
create table if not exists public.verification_reviews (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores (id) on delete cascade,
  reviewer_id uuid references auth.users (id) on delete set null,
  decision text not null check (decision in ('verified', 'rejected')),
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists verification_reviews_store_idx
  on public.verification_reviews (store_id);

alter table public.verification_reviews enable row level security;
revoke all on public.verification_reviews from anon, authenticated;
grant select on public.verification_reviews to authenticated;

drop policy if exists "verification_reviews_admin_read" on public.verification_reviews;
create policy "verification_reviews_admin_read"
  on public.verification_reviews for select
  to authenticated
  using (public.is_admin());

-- =============================================================
-- 4. Storage: berkas verifikasi
-- =============================================================
-- Path: {uid}/{storeId}/{ktp|store_photo|selfie|nib}.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verifications', 'verifications', false, 10485760, array['image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Pemilik boleh menulis hanya ke folder tokonya sendiri, dan hanya selama
-- toko itu belum/ditolak verifikasinya — berkas tidak bisa ditukar setelah
-- diajukan atau disetujui.
create or replace function public.can_write_verification_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.stores s
    where s.owner_uid = auth.uid()
      and (storage.foldername(p_name))[1] = auth.uid()::text
      and (storage.foldername(p_name))[2] = s.id::text
      and cardinality(storage.foldername(p_name)) = 2
      and storage.filename(p_name) in ('ktp.jpg', 'store_photo.jpg', 'selfie.jpg', 'nib.jpg')
      and s.verification_status in ('unverified', 'rejected')
  );
$$;

revoke all on function public.can_write_verification_file(text) from public, anon;
grant execute on function public.can_write_verification_file(text) to authenticated;

drop policy if exists "verification_files_owner_read" on storage.objects;
create policy "verification_files_owner_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'verifications'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification_files_admin_read" on storage.objects;
create policy "verification_files_admin_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'verifications' and public.is_admin());

drop policy if exists "verification_files_owner_write" on storage.objects;
create policy "verification_files_owner_write"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'verifications'
    and public.can_write_verification_file(name)
  );

drop policy if exists "verification_files_owner_update" on storage.objects;
create policy "verification_files_owner_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'verifications'
    and public.can_write_verification_file(name)
  )
  with check (
    bucket_id = 'verifications'
    and public.can_write_verification_file(name)
  );

-- Dipakai saat pemilik menghapus akunnya.
drop policy if exists "verification_files_owner_delete" on storage.objects;
create policy "verification_files_owner_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'verifications'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =============================================================
-- 5. Storage: cadangan data toko
-- =============================================================
-- Path: {uid}/{storeId}.json.gz — satu berkas cadangan terbaru per toko.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('backups', 'backups', false, 52428800, array['application/gzip'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.owns_backup_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (storage.foldername(p_name))[1] = auth.uid()::text
    and cardinality(storage.foldername(p_name)) = 1
    and exists (
      select 1 from public.stores s
      where s.owner_uid = auth.uid()
        and s.id::text || '.json.gz' = storage.filename(p_name)
    );
$$;

revoke all on function public.owns_backup_file(text) from public, anon;
grant execute on function public.owns_backup_file(text) to authenticated;

drop policy if exists "backups_owner_read" on storage.objects;
create policy "backups_owner_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "backups_owner_insert" on storage.objects;
create policy "backups_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'backups' and public.owns_backup_file(name));

drop policy if exists "backups_owner_update" on storage.objects;
create policy "backups_owner_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'backups' and public.owns_backup_file(name))
  with check (bucket_id = 'backups' and public.owns_backup_file(name));

drop policy if exists "backups_owner_delete" on storage.objects;
create policy "backups_owner_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =============================================================
-- 6. Alur verifikasi
-- =============================================================
create or replace function public.submit_store_verification(
  p_store_id uuid,
  p_consent_version text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_status text;
  v_prefix text;
  v_found int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(trim(p_consent_version), '') = '' then
    raise exception 'consent version required' using errcode = '22023';
  end if;

  select owner_uid, verification_status into v_owner, v_status
  from public.stores where id = p_store_id
  for update;

  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'store not found' using errcode = 'P0002';
  end if;
  if v_status not in ('unverified', 'rejected') then
    raise exception 'store cannot be submitted from status %', v_status
      using errcode = '22023';
  end if;

  -- Tiga berkas wajib harus sudah ada di Storage.
  v_prefix := v_owner::text || '/' || p_store_id::text || '/';
  select count(*) into v_found
  from storage.objects
  where bucket_id = 'verifications'
    and name in (v_prefix || 'ktp.jpg', v_prefix || 'store_photo.jpg', v_prefix || 'selfie.jpg');
  if v_found < 3 then
    raise exception 'required documents missing' using errcode = '22023';
  end if;

  update public.stores
  set verification_status = 'pending',
      rejection_reason = null,
      verification_submitted_at = now(),
      verification_reviewed_at = null,
      identity_consent_version = p_consent_version,
      identity_consent_at = now()
  where id = p_store_id;
end;
$$;

revoke all on function public.submit_store_verification(uuid, text) from public, anon;
grant execute on function public.submit_store_verification(uuid, text) to authenticated;

create or replace function public.review_store_verification(
  p_store_id uuid,
  p_status text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('verified', 'rejected') then
    raise exception 'invalid status: %', p_status using errcode = '22023';
  end if;
  if p_status = 'rejected' and coalesce(trim(p_reason), '') = '' then
    raise exception 'rejection reason required' using errcode = '22023';
  end if;

  update public.stores
  set verification_status = p_status,
      rejection_reason = case when p_status = 'rejected' then trim(p_reason) else null end,
      verification_reviewed_at = now()
  where id = p_store_id
    and verification_status = 'pending';

  if not found then
    raise exception 'store is not pending review' using errcode = 'P0002';
  end if;

  insert into public.verification_reviews (store_id, reviewer_id, decision, reason)
  values (
    p_store_id,
    auth.uid(),
    p_status,
    case when p_status = 'rejected' then trim(p_reason) else null end
  );
end;
$$;

revoke all on function public.review_store_verification(uuid, text, text) from public, anon;
grant execute on function public.review_store_verification(uuid, text, text) to authenticated;

-- Antrean peninjauan untuk panel admin, lengkap dengan email pemilik.
drop function if exists public.admin_pending_verifications();
create function public.admin_pending_verifications()
returns table (
  store_id uuid,
  owner_uid uuid,
  owner_email text,
  name text,
  category text,
  address text,
  submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;

  return query
  select s.id, s.owner_uid, u.email::text, s.name, s.category, s.address,
         s.verification_submitted_at
  from public.stores s
  join auth.users u on u.id = s.owner_uid
  where s.verification_status = 'pending'
  order by s.verification_submitted_at asc nulls last;
end;
$$;

revoke all on function public.admin_pending_verifications() from public, anon;
grant execute on function public.admin_pending_verifications() to authenticated;

-- =============================================================
-- 7. Kuota bantuan AI (dipakai Edge Function `parse-transaction`)
-- =============================================================
create table if not exists public.llm_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  calls int not null default 0,
  primary key (user_id, day)
);

alter table public.llm_usage enable row level security;
revoke all on public.llm_usage from anon, authenticated;

-- Menambah hitungan pemakaian hari ini dan mengembalikan true bila masih di
-- bawah batas. Dipanggil Edge Function dengan JWT pengguna.
create or replace function public.consume_llm_quota(p_daily_limit int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_calls int;
begin
  if auth.uid() is null then
    return false;
  end if;

  insert into public.llm_usage (user_id, day, calls)
  values (auth.uid(), (now() at time zone 'Asia/Jakarta')::date, 1)
  on conflict (user_id, day) do update set calls = public.llm_usage.calls + 1
  returning calls into v_calls;

  return v_calls <= greatest(p_daily_limit, 0);
end;
$$;

revoke all on function public.consume_llm_quota(int) from public, anon;
grant execute on function public.consume_llm_quota(int) to authenticated;

-- =============================================================
-- 8. Hapus akun
-- =============================================================
-- Aplikasi menghapus berkas Storage milik pengguna lebih dulu (lewat policy
-- delete di atas), lalu memanggil fungsi ini. Toko, riwayat verifikasi, dan
-- pemakaian AI ikut terhapus lewat ON DELETE CASCADE.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- =============================================================
-- 9. Menambah admin
-- =============================================================
-- Jalankan sekali per admin, ganti emailnya:
--
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'admin@contoh.com'
--   on conflict do nothing;
