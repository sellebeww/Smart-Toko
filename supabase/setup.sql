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

-- Sinkronisasi antar-HP dinyalakan pemilik lewat set_store_sync(); klien
-- tidak bisa mengubah kolom ini langsung (tidak ada hak kolomnya).
alter table public.stores
  add column if not exists sync_enabled boolean not null default false;

-- Karyawan toko. Pemilik tidak dicatat di sini: pemilik = stores.owner_uid.
create table if not exists public.store_members (
  store_id uuid not null references public.stores (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'staff' check (role = 'staff'),
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

create index if not exists store_members_user_idx
  on public.store_members (user_id);

alter table public.store_members enable row level security;
revoke all on public.store_members from anon, authenticated;

create or replace function public.is_store_staff(p_store uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.store_members
    where store_id = p_store and user_id = auth.uid()
  );
$$;

revoke all on function public.is_store_staff(uuid) from public, anon;
grant execute on function public.is_store_staff(uuid) to authenticated;

-- 'owner', 'staff', atau null bila bukan siapa-siapa di toko itu.
create or replace function public.store_role(p_store uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (
      select 1 from public.stores where id = p_store and owner_uid = auth.uid()
    ) then 'owner'
    when public.is_store_staff(p_store) then 'staff'
  end;
$$;

revoke all on function public.store_role(uuid) from public, anon;
grant execute on function public.store_role(uuid) to authenticated;

-- Policy versi lama.
drop policy if exists "stores_select_any_authenticated" on public.stores;

drop policy if exists "stores_select_own_or_admin" on public.stores;
drop policy if exists "stores_select_member_or_admin" on public.stores;
create policy "stores_select_member_or_admin"
  on public.stores for select
  to authenticated
  using (
    owner_uid = auth.uid()
    or public.is_store_staff(id)
    or public.is_admin()
  );

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

-- Mengembalikan satu jatah bila panggilan ke model gagal di sisi server
-- (bukan salah pengguna), supaya kegagalan tidak menghabiskan kuota harian.
create or replace function public.refund_llm_quota()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  update public.llm_usage
  set calls = greatest(calls - 1, 0)
  where user_id = auth.uid()
    and day = (now() at time zone 'Asia/Jakarta')::date;
end;
$$;

revoke all on function public.refund_llm_quota() from public, anon;
grant execute on function public.refund_llm_quota() to authenticated;

-- =============================================================
-- 7b. Laporan error dari aplikasi
-- =============================================================
-- Pengganti layanan crash reporting pihak ketiga: aplikasi melaporkan error
-- tak tertangani lewat fungsi di bawah. Isinya hanya jenis error, pesan dan
-- stack yang dipotong, versi aplikasi, dan platform — tanpa data transaksi.
-- Tabel tidak bisa dibaca klien; baca lewat SQL Editor / dashboard.
create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  app_version text,
  platform text,
  error_type text,
  message text,
  stack text
);

alter table public.client_errors enable row level security;
revoke all on public.client_errors from anon, authenticated;

create or replace function public.report_client_error(
  p_app_version text,
  p_platform text,
  p_error_type text,
  p_message text,
  p_stack text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  -- Batas harian per pengguna agar tidak bisa dipakai membanjiri tabel.
  if (
    select count(*) from public.client_errors
    where user_id = auth.uid() and created_at > now() - interval '1 day'
  ) >= 50 then
    return;
  end if;

  insert into public.client_errors
    (user_id, app_version, platform, error_type, message, stack)
  values (
    auth.uid(),
    left(p_app_version, 32),
    left(p_platform, 32),
    left(p_error_type, 200),
    left(p_message, 1000),
    left(p_stack, 4000)
  );
end;
$$;

revoke all on function public.report_client_error(text, text, text, text, text)
  from public, anon;
grant execute on function public.report_client_error(text, text, text, text, text)
  to authenticated;

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
-- 10. Sinkronisasi antar-HP dan karyawan
-- =============================================================
-- Data toko (transaksi, barang, stok, kontak, kasbon) disimpan per baris
-- sebagai JSON. Tiap perubahan mendapat nomor versi yang terus naik; HP
-- menarik semua baris dengan versi di atas yang terakhir ia lihat.
-- Klien tidak bisa membaca/menulis tabel ini langsung: hanya lewat
-- sync_push / sync_pull, yang memeriksa peran pemanggil.

create sequence if not exists public.sync_version_seq;

create table if not exists public.sync_rows (
  store_id uuid not null references public.stores (id) on delete cascade,
  table_name text not null check (table_name in (
    'products', 'contacts', 'transactions', 'transaction_items',
    'stock_movements', 'debt_payments'
  )),
  row_id text not null,
  data jsonb,
  deleted boolean not null default false,
  version bigint not null,
  created_by uuid references auth.users (id) on delete set null,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (store_id, table_name, row_id)
);

create index if not exists sync_rows_store_version_idx
  on public.sync_rows (store_id, version);

alter table public.sync_rows enable row level security;
revoke all on public.sync_rows from anon, authenticated;

create table if not exists public.store_invites (
  code text primary key,
  store_id uuid not null references public.stores (id) on delete cascade,
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_by uuid references auth.users (id) on delete set null,
  used_at timestamptz
);

alter table public.store_invites enable row level security;
revoke all on public.store_invites from anon, authenticated;

-- Membatasi tebakan kode undangan.
create table if not exists public.invite_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  attempts int not null default 0,
  primary key (user_id, day)
);

alter table public.invite_attempts enable row level security;
revoke all on public.invite_attempts from anon, authenticated;

create or replace function public.set_store_sync(
  p_store uuid,
  p_enabled boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.store_role(p_store) is distinct from 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  update public.stores set sync_enabled = coalesce(p_enabled, false)
  where id = p_store;
  -- Mematikan = data toko di server dihapus, karyawan dan undangan dicabut.
  if not coalesce(p_enabled, false) then
    delete from public.sync_rows where store_id = p_store;
    delete from public.store_members where store_id = p_store;
    delete from public.store_invites where store_id = p_store;
  end if;
end;
$$;

revoke all on function public.set_store_sync(uuid, boolean) from public, anon;
grant execute on function public.set_store_sync(uuid, boolean) to authenticated;

create or replace function public.create_store_invite(p_store uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if public.store_role(p_store) is distinct from 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  if not coalesce(
    (select sync_enabled from public.stores where id = p_store), false
  ) then
    raise exception 'sync required' using errcode = '22023';
  end if;
  delete from public.store_invites
  where store_id = p_store and used_at is null and expires_at < now();
  if (
    select count(*) from public.store_invites
    where store_id = p_store and used_at is null
  ) >= 5 then
    raise exception 'too many active invites' using errcode = '22023';
  end if;
  -- 10 karakter heksadesimal: sekitar satu triliun kemungkinan.
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.store_invites (code, store_id, created_by, expires_at)
  values (v_code, p_store, auth.uid(), now() + interval '48 hours');
  return v_code;
end;
$$;

revoke all on function public.create_store_invite(uuid) from public, anon;
grant execute on function public.create_store_invite(uuid) to authenticated;

-- Mengembalikan id toko, atau null bila kodenya salah/kedaluwarsa/terpakai.
create or replace function public.accept_store_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.store_invites%rowtype;
  v_attempts int;
  v_owner uuid;
  v_sync boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.invite_attempts (user_id, day, attempts)
  values (auth.uid(), (now() at time zone 'Asia/Jakarta')::date, 1)
  on conflict (user_id, day)
    do update set attempts = public.invite_attempts.attempts + 1
  returning attempts into v_attempts;
  if v_attempts > 20 then
    raise exception 'too many attempts' using errcode = '54000';
  end if;

  select * into v_invite from public.store_invites
  where code = upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'))
    and used_at is null
    and expires_at > now()
  for update;
  if not found then
    -- Bukan exception: exception membatalkan seluruh fungsi, termasuk
    -- penambahan hitungan percobaan di atas, sehingga tebakan tak terbatas.
    return null;
  end if;

  select owner_uid, sync_enabled into v_owner, v_sync
  from public.stores where id = v_invite.store_id;
  if v_owner = auth.uid() then
    raise exception 'own store' using errcode = '22023';
  end if;
  if not coalesce(v_sync, false) then
    raise exception 'sync disabled' using errcode = '22023';
  end if;

  insert into public.store_members (store_id, user_id)
  values (v_invite.store_id, auth.uid())
  on conflict do nothing;
  update public.store_invites
  set used_by = auth.uid(), used_at = now()
  where code = v_invite.code;
  return v_invite.store_id;
end;
$$;

revoke all on function public.accept_store_invite(text) from public, anon;
grant execute on function public.accept_store_invite(text) to authenticated;

drop function if exists public.store_member_list(uuid);
create function public.store_member_list(p_store uuid)
returns table (user_id uuid, email text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.store_role(p_store) is distinct from 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  return query
  select m.user_id, coalesce(u.email::text, '+' || u.phone::text), m.created_at
  from public.store_members m
  join auth.users u on u.id = m.user_id
  where m.store_id = p_store
  order by m.created_at;
end;
$$;

revoke all on function public.store_member_list(uuid) from public, anon;
grant execute on function public.store_member_list(uuid) to authenticated;

create or replace function public.remove_store_member(
  p_store uuid,
  p_user uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.store_role(p_store) is distinct from 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  delete from public.store_members
  where store_id = p_store and user_id = p_user;
end;
$$;

revoke all on function public.remove_store_member(uuid, uuid) from public, anon;
grant execute on function public.remove_store_member(uuid, uuid) to authenticated;

create or replace function public.leave_store(p_store uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.store_members
  where store_id = p_store and user_id = auth.uid();
$$;

revoke all on function public.leave_store(uuid) from public, anon;
grant execute on function public.leave_store(uuid) to authenticated;

-- Mengirim perubahan dari HP. p_rows: [{table, id, deleted, data}, ...].
--
-- Karyawan boleh menambah baris apa pun, tetapi hanya boleh mengubah atau
-- menghapus baris buatannya sendiri — kecuali mengubah (bukan menghapus)
-- barang dan kontak. Perubahan yang ditolak tidak membuat seluruh kiriman
-- gagal: versi baris aslinya dinaikkan, sehingga HP karyawan menariknya
-- kembali dan kembali sama dengan server. Karyawan tidak pernah bisa
-- menulis modal (HPP).
create or replace function public.sync_push(p_store uuid, p_rows jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.store_role(p_store);
  v_row jsonb;
  v_table text;
  v_id text;
  v_deleted boolean;
  v_data jsonb;
  v_existing public.sync_rows%rowtype;
  v_exists boolean;
  v_allowed boolean;
  v_cost jsonb;
  v_version bigint;
  v_max bigint := 0;
begin
  if v_role is null then
    raise exception 'not a member' using errcode = '42501';
  end if;
  if not coalesce(
    (select sync_enabled from public.stores where id = p_store), false
  ) then
    raise exception 'sync disabled' using errcode = '22023';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array'
     or jsonb_array_length(p_rows) > 500 then
    raise exception 'invalid batch' using errcode = '22023';
  end if;

  -- Satu pengirim per toko pada satu waktu: urutan versi = urutan commit,
  -- jadi HP yang menarik tidak pernah melompati perubahan yang belum
  -- ter-commit.
  perform pg_advisory_xact_lock(hashtextextended(p_store::text, 0));

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_table := v_row->>'table';
    v_id := v_row->>'id';
    v_deleted := coalesce((v_row->>'deleted')::boolean, false);
    v_data := v_row->'data';

    if v_table is null or v_table not in (
         'products', 'contacts', 'transactions', 'transaction_items',
         'stock_movements', 'debt_payments'
       )
       or coalesce(v_id, '') = '' or length(v_id) > 64 then
      raise exception 'invalid row' using errcode = '22023';
    end if;
    if not v_deleted and (
         jsonb_typeof(v_data) is distinct from 'object'
         or octet_length(v_data::text) > 20000
         or (v_data ? 'store_id' and v_data->>'store_id' <> p_store::text)
       ) then
      raise exception 'invalid row data' using errcode = '22023';
    end if;

    select * into v_existing from public.sync_rows
    where store_id = p_store and table_name = v_table and row_id = v_id
    for update;
    v_exists := found;

    v_allowed := true;
    if v_role = 'staff' then
      if v_exists and v_existing.created_by is distinct from auth.uid() then
        v_allowed := not v_deleted and v_table in ('products', 'contacts');
      end if;
      if v_allowed and not v_deleted and v_table = 'products' then
        v_data := v_data || jsonb_build_object(
          'cost_price',
          case when v_exists then coalesce(v_existing.data->'cost_price', 'null'::jsonb)
               else 'null'::jsonb end
        );
      end if;
      if v_allowed and not v_deleted and v_table = 'transaction_items' then
        if v_exists then
          v_cost := coalesce(v_existing.data->'unit_cost', 'null'::jsonb);
        else
          -- Penjualan oleh karyawan memakai modal katalog saat itu.
          select coalesce(p.data->'cost_price', 'null'::jsonb) into v_cost
          from public.sync_rows p
          where p.store_id = p_store and p.table_name = 'products'
            and p.row_id = v_data->>'product_id' and not p.deleted
            and exists (
              select 1 from public.sync_rows t
              where t.store_id = p_store and t.table_name = 'transactions'
                and t.row_id = v_data->>'transaction_id'
                and t.data->>'category' = 'penjualan'
            );
          v_cost := coalesce(v_cost, 'null'::jsonb);
        end if;
        v_data := v_data || jsonb_build_object('unit_cost', v_cost);
      end if;
    end if;

    v_version := nextval('public.sync_version_seq');
    if not v_allowed then
      update public.sync_rows set version = v_version
      where store_id = p_store and table_name = v_table and row_id = v_id;
      v_max := greatest(v_max, v_version);
      continue;
    end if;

    insert into public.sync_rows (
      store_id, table_name, row_id, data, deleted, version,
      created_by, updated_by, updated_at
    ) values (
      p_store, v_table, v_id,
      case when v_deleted then null else v_data end,
      v_deleted, v_version, auth.uid(), auth.uid(), now()
    )
    on conflict (store_id, table_name, row_id) do update
      set data = excluded.data,
          deleted = excluded.deleted,
          version = excluded.version,
          updated_by = excluded.updated_by,
          updated_at = now();
    v_max := greatest(v_max, v_version);

    -- Menghapus transaksi ikut menghapus barang, pembayaran, dan stok dari
    -- pembeliannya, seperti ON DELETE CASCADE di HP.
    if v_deleted and v_table = 'transactions' then
      with items as (
        select row_id from public.sync_rows
        where store_id = p_store and table_name = 'transaction_items'
          and not deleted and data->>'transaction_id' = v_id
      )
      update public.sync_rows
      set deleted = true, data = null,
          version = nextval('public.sync_version_seq'),
          updated_by = auth.uid(), updated_at = now()
      where store_id = p_store and not deleted and (
        (table_name = 'transaction_items' and row_id in (select row_id from items))
        or (table_name = 'stock_movements'
            and data->>'transaction_item_id' in (select row_id from items))
        or (table_name = 'debt_payments' and data->>'transaction_id' = v_id)
      );
    end if;
  end loop;

  return v_max;
end;
$$;

revoke all on function public.sync_push(uuid, jsonb) from public, anon;
grant execute on function public.sync_push(uuid, jsonb) to authenticated;

-- Menarik perubahan sesudah versi p_after, terlama dulu. Modal (HPP) tidak
-- pernah dikirim ke HP karyawan.
drop function if exists public.sync_pull(uuid, bigint, int);
create function public.sync_pull(
  p_store uuid,
  p_after bigint,
  p_limit int default 500
) returns table (
  table_name text,
  row_id text,
  data jsonb,
  deleted boolean,
  version bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.store_role(p_store);
begin
  if v_role is null then
    raise exception 'not a member' using errcode = '42501';
  end if;
  return query
  select s.table_name, s.row_id,
         case when v_role = 'staff' and s.data is not null
                   and s.table_name in ('products', 'transaction_items')
              then s.data - 'cost_price' - 'unit_cost'
              else s.data end,
         s.deleted, s.version
  from public.sync_rows s
  where s.store_id = p_store and s.version > coalesce(p_after, 0)
  order by s.version
  limit least(greatest(coalesce(p_limit, 500), 1), 1000);
end;
$$;

revoke all on function public.sync_pull(uuid, bigint, int) from public, anon;
grant execute on function public.sync_pull(uuid, bigint, int) to authenticated;

-- Toko tempat pengguna menjadi karyawan (untuk daftar toko di HP-nya).
drop function if exists public.my_staff_stores();
create function public.my_staff_stores()
returns setof public.stores
language sql
stable
security definer
set search_path = public
as $$
  select s.* from public.stores s
  join public.store_members m on m.store_id = s.id
  where m.user_id = auth.uid() and s.sync_enabled
  order by s.created_at;
$$;

revoke all on function public.my_staff_stores() from public, anon;
grant execute on function public.my_staff_stores() to authenticated;

-- =============================================================
-- 9. Menambah admin
-- =============================================================
-- Jalankan sekali per admin, ganti emailnya:
--
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'admin@contoh.com'
--   on conflict do nothing;
