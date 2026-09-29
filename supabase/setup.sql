-- Setup Supabase untuk Smart Toko.
-- Jalankan seluruh isi file ini sekali di Supabase Dashboard > SQL Editor.
-- Aman dijalankan ulang (drop-lalu-create dipakai di mana Postgres tidak
-- punya "create ... if not exists" untuk objek itu, misalnya policy).

-- =============================================================
-- 1. Tabel `stores`
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

create index if not exists stores_owner_uid_idx on public.stores (owner_uid);
create index if not exists stores_verification_status_idx
  on public.stores (verification_status);

-- Realtime: dibutuhkan StoreRepository.watchStore/watchStoresForUser/watchPendingStores
-- (semuanya pakai `.stream()` di sisi Flutter). Dibungkus DO block supaya
-- tidak error kalau skrip ini dijalankan dua kali.
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

-- =============================================================
-- 2. Row Level Security
-- =============================================================
alter table public.stores enable row level security;

drop policy if exists "stores_select_any_authenticated" on public.stores;
-- Dibaca siapa pun yang login, bukan cuma pemilik — dipakai panel admin demo
-- (AdminVerificationScreen) yang tidak punya sistem role sungguhan. Data di
-- sini bukan data sensitif (nama/alamat/status); KTP & selfie ada di Storage,
-- bukan di tabel ini.
create policy "stores_select_any_authenticated"
  on public.stores for select
  to authenticated
  using (true);

drop policy if exists "stores_insert_own" on public.stores;
create policy "stores_insert_own"
  on public.stores for insert
  to authenticated
  with check (owner_uid = auth.uid());

drop policy if exists "stores_update_own" on public.stores;
-- Pemilik boleh ubah field apa pun miliknya sendiri (termasuk submit
-- verifikasi). Penyetujuan/penolakan oleh "admin" TIDAK lewat policy ini,
-- tapi lewat fungsi review_store_verification di bawah, supaya user lain
-- tidak pernah bisa mengubah kolom selain status verifikasi.
create policy "stores_update_own"
  on public.stores for update
  to authenticated
  using (owner_uid = auth.uid())
  with check (owner_uid = auth.uid());

-- Tidak ada policy delete = delete selalu ditolak.

-- =============================================================
-- 3. Fungsi admin demo: setujui/tolak verifikasi
-- =============================================================
-- SECURITY DEFINER supaya fungsi ini bisa mengubah baris siapa pun (perlu,
-- karena ini simulasi admin tanpa role sungguhan), TAPI hanya lewat fungsi
-- ini — bukan lewat UPDATE bebas ke tabel — jadi user lain tetap tidak bisa
-- menyentuh nama/alamat/kategori toko orang lain, cuma tiga kolom status ini.
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
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_status not in ('verified', 'rejected') then
    raise exception 'invalid status: %', p_status;
  end if;

  update public.stores
  set verification_status = p_status,
      rejection_reason = case when p_status = 'rejected' then p_reason else null end,
      verification_reviewed_at = now()
  where id = p_store_id;
end;
$$;

grant execute on function public.review_store_verification(uuid, text, text)
  to authenticated;

-- =============================================================
-- 4. Storage bucket + policy untuk berkas verifikasi
-- =============================================================
insert into storage.buckets (id, name, public)
values ('verifications', 'verifications', false)
on conflict (id) do nothing;

-- Path berkas: {uid}/{storeId}/{namaFile} — folder pertama harus sama dengan
-- uid yang login, jadi user lain tidak bisa baca/tulis punya orang lain.
drop policy if exists "verification_files_owner_read" on storage.objects;
create policy "verification_files_owner_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'verifications'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification_files_owner_write" on storage.objects;
create policy "verification_files_owner_write"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'verifications'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification_files_owner_update" on storage.objects;
create policy "verification_files_owner_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'verifications'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
