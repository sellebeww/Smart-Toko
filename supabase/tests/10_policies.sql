-- Uji kebijakan keamanan supabase/setup.sql. Dijalankan lewat run.sh setelah
-- 00_shim.sql dan setup.sql. Berhenti di kegagalan pertama (ON_ERROR_STOP).
--
-- Baris "ok" dicetak sebagai NOTICE; kegagalan melempar exception.

\set ON_ERROR_STOP 1
\o /dev/null

create schema test;
grant usage on schema test to public;

create function test.ok(cond boolean, label text) returns void
language plpgsql as $$
begin
  if cond is not true then
    raise exception 'GAGAL: %', label;
  end if;
  raise notice 'ok   %', label;
end $$;

-- Pernyataan [stmt] harus ditolak dengan SQLSTATE [expected].
create function test.denied(stmt text, label text, expected text default '42501')
returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate = expected then
      raise notice 'ok   %', label;
      return;
    end if;
    raise exception 'GAGAL: % (error tidak sesuai: % %)', label, sqlstate, sqlerrm;
  end;
  raise exception 'GAGAL: % (seharusnya ditolak)', label;
end $$;

create function test.login(uid uuid) returns void
language sql as $$
  select set_config('request.jwt.claim.sub', uid::text, false)
$$;

-- ---------------------------------------------------------------- data awal
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'alice@contoh.com'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'bob@contoh.com'),
  ('cccccccc-0000-0000-0000-000000000003', 'carol@contoh.com');
insert into public.admins (user_id) values
  ('cccccccc-0000-0000-0000-000000000003');

-- ------------------------------------------------------------------- alice
reset role; set role authenticated;
select test.login('aaaaaaaa-0000-0000-0000-000000000001');

insert into public.stores (id, owner_uid, name, category, address) values
  ('11111111-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001', 'Warung Alice', 'warteg', 'Jl. 1');
select test.ok(true, 'pemilik bisa membuat tokonya');

select test.denied($$insert into public.stores (id, owner_uid, name, category)
  values ('33333333-0000-0000-0000-000000000003',
          'bbbbbbbb-0000-0000-0000-000000000002', 'Palsu', 'warteg')$$,
  'tidak bisa membuat toko atas nama orang lain');
select test.denied($$insert into public.stores
  (id, owner_uid, name, category, verification_status)
  values ('33333333-0000-0000-0000-000000000004',
          'aaaaaaaa-0000-0000-0000-000000000001', 'X', 'warteg', 'verified')$$,
  'tidak bisa mengisi status verifikasi saat membuat toko');
select test.denied($$update public.stores set verification_status = 'verified'
  where id = '11111111-0000-0000-0000-000000000001'$$,
  'tidak bisa menandai tokonya sendiri verified');
select test.denied($$update public.stores
  set owner_uid = 'bbbbbbbb-0000-0000-0000-000000000002'
  where id = '11111111-0000-0000-0000-000000000001'$$,
  'tidak bisa memindahkan kepemilikan toko');
select test.denied($$update public.stores set name = ''
  where id = '11111111-0000-0000-0000-000000000001'$$,
  'nama toko kosong ditolak', '23514');
update public.stores set name = 'Warung Alice 2'
  where id = '11111111-0000-0000-0000-000000000001';
select test.ok((select name from public.stores
  where id = '11111111-0000-0000-0000-000000000001') = 'Warung Alice 2',
  'pemilik bisa mengubah nama tokonya');
select test.denied($$delete from public.stores
  where id = '11111111-0000-0000-0000-000000000001'$$,
  'pemilik tidak bisa menghapus toko langsung');
select test.denied($$select * from public.admins$$, 'tabel admins tertutup');
select test.denied($$select * from public.llm_usage$$, 'tabel llm_usage tertutup');
select test.denied($$select * from public.client_errors$$,
  'tabel client_errors tertutup');
select test.ok(not public.is_admin(), 'alice bukan admin');

-- --------------------------------------------------------------------- bob
reset role; set role authenticated;
select test.login('bbbbbbbb-0000-0000-0000-000000000002');

insert into public.stores (id, owner_uid, name, category, address) values
  ('22222222-0000-0000-0000-000000000002',
   'bbbbbbbb-0000-0000-0000-000000000002', 'Warung Bob', 'warteg', 'Jl. 2');
select test.ok((select count(*) from public.stores
  where id = '11111111-0000-0000-0000-000000000001') = 0,
  'bob tidak melihat toko alice');
select test.ok((select count(*) from public.stores) = 1,
  'bob hanya melihat tokonya sendiri');

-- Mengubah toko orang lain: tidak error, tapi 0 baris terpengaruh.
with changed as (
  update public.stores set name = 'Diretas'
  where id = '11111111-0000-0000-0000-000000000001' returning 1
) select test.ok((select count(*) from changed) = 0,
  'bob tidak bisa mengubah toko alice');

-- ----------------------------------------------------- berkas verifikasi
reset role; set role authenticated;
select test.login('aaaaaaaa-0000-0000-0000-000000000001');

insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/ktp.jpg');
select test.ok(true, 'pemilik bisa mengunggah KTP ke folder tokonya');

select test.denied($$insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/virus.exe')$$,
  'nama berkas di luar empat dokumen ditolak');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/sub/ktp.jpg')$$,
  'folder terlalu dalam ditolak');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('verifications', 'bbbbbbbb-0000-0000-0000-000000000002/22222222-0000-0000-0000-000000000002/ktp.jpg')$$,
  'tidak bisa menulis ke folder orang lain');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/22222222-0000-0000-0000-000000000002/ktp.jpg')$$,
  'tidak bisa menulis ke toko orang lain di bawah foldernya');

select test.denied($$select public.submit_store_verification(
  '11111111-0000-0000-0000-000000000001', 'v1')$$,
  'pengajuan ditolak bila dokumen wajib belum lengkap', '22023');

insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/store_photo.jpg'),
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/selfie.jpg');
select public.submit_store_verification(
  '11111111-0000-0000-0000-000000000001', 'v1');
select test.ok((select verification_status from public.stores
  where id = '11111111-0000-0000-0000-000000000001') = 'pending',
  'pengajuan lengkap mengubah status menjadi pending');

select test.denied($$insert into storage.objects (bucket_id, name) values
  ('verifications', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001/nib.jpg')$$,
  'berkas tidak bisa ditambah setelah diajukan');
select test.denied($$select public.submit_store_verification(
  '11111111-0000-0000-0000-000000000001', 'v1')$$,
  'tidak bisa mengajukan dua kali', '22023');
select test.denied($$select public.review_store_verification(
  '11111111-0000-0000-0000-000000000001', 'verified')$$,
  'pemilik tidak bisa menyetujui tokonya sendiri');
select test.denied($$select * from public.admin_pending_verifications()$$,
  'bukan admin tidak bisa membuka antrean');
select test.ok((select count(*) from public.verification_reviews) = 0,
  'bukan admin tidak melihat riwayat peninjauan');

reset role; set role authenticated;
select test.login('bbbbbbbb-0000-0000-0000-000000000002');
select test.ok((select count(*) from storage.objects
  where bucket_id = 'verifications') = 0,
  'bob tidak bisa membaca berkas verifikasi alice');

-- ------------------------------------------------------------------- admin
reset role; set role authenticated;
select test.login('cccccccc-0000-0000-0000-000000000003');
select test.ok(public.is_admin(), 'carol admin');
select test.ok((select count(*) from public.stores) = 2,
  'admin melihat semua toko');
select test.ok((select count(*) from storage.objects
  where bucket_id = 'verifications') = 3,
  'admin bisa membaca berkas verifikasi');
select test.ok((select count(*) from public.admin_pending_verifications()
  where owner_email = 'alice@contoh.com') = 1,
  'antrean admin memuat pengajuan alice');
select test.denied($$select public.review_store_verification(
  '11111111-0000-0000-0000-000000000001', 'bogus')$$,
  'status keputusan tidak dikenal ditolak', '22023');
select test.denied($$select public.review_store_verification(
  '11111111-0000-0000-0000-000000000001', 'rejected', '  ')$$,
  'penolakan tanpa alasan ditolak', '22023');
select public.review_store_verification(
  '11111111-0000-0000-0000-000000000001', 'verified');
select test.ok((select verification_status from public.stores
  where id = '11111111-0000-0000-0000-000000000001') = 'verified',
  'admin bisa menyetujui');
select test.denied($$select public.review_store_verification(
  '11111111-0000-0000-0000-000000000001', 'verified')$$,
  'toko yang tidak pending tidak bisa ditinjau lagi', 'P0002');
select test.ok((select count(*) from public.verification_reviews) = 1,
  'keputusan tercatat di riwayat');

-- ---------------------------------------------------------------- cadangan
reset role; set role authenticated;
select test.login('aaaaaaaa-0000-0000-0000-000000000001');
insert into storage.objects (bucket_id, name) values
  ('backups', 'aaaaaaaa-0000-0000-0000-000000000001/11111111-0000-0000-0000-000000000001.json.gz');
select test.ok(true, 'pemilik bisa mengunggah cadangan tokonya');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('backups', 'aaaaaaaa-0000-0000-0000-000000000001/bukan-tokonya.json.gz')$$,
  'cadangan untuk toko yang bukan miliknya ditolak');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('backups', 'aaaaaaaa-0000-0000-0000-000000000001/sub/11111111-0000-0000-0000-000000000001.json.gz')$$,
  'cadangan di subfolder ditolak');
select test.denied($$insert into storage.objects (bucket_id, name) values
  ('backups', 'bbbbbbbb-0000-0000-0000-000000000002/22222222-0000-0000-0000-000000000002.json.gz')$$,
  'tidak bisa menulis cadangan di folder orang lain');
select test.ok((select count(*) from storage.objects
  where bucket_id = 'backups') = 1, 'pemilik membaca cadangannya');

reset role; set role authenticated;
select test.login('bbbbbbbb-0000-0000-0000-000000000002');
select test.ok((select count(*) from storage.objects
  where bucket_id = 'backups') = 0, 'bob tidak membaca cadangan alice');
with removed as (
  delete from storage.objects where bucket_id = 'backups' returning 1
) select test.ok((select count(*) from removed) = 0,
  'bob tidak bisa menghapus cadangan alice');

-- ------------------------------------------------------------ kuota AI
reset role; set role authenticated;
select test.login('aaaaaaaa-0000-0000-0000-000000000001');
select test.ok(public.consume_llm_quota(2), 'panggilan 1 dalam batas');
select test.ok(public.consume_llm_quota(2), 'panggilan 2 dalam batas');
select public.refund_llm_quota();
select test.ok(public.consume_llm_quota(2),
  'jatah yang dikembalikan bisa dipakai lagi');
select test.ok(not public.consume_llm_quota(2), 'melewati batas ditolak');
select test.denied($$select * from public.llm_usage$$, 'kuota tidak bisa dibaca klien');

-- ----------------------------------------------------- laporan error
select public.report_client_error('1.0.0+1', 'android', 'StateError',
  repeat('x', 5000), 'stack');
reset role;
select test.ok((select length(message) from public.client_errors) = 1000,
  'pesan error dipotong 1000 karakter');
set role authenticated;
select test.login('aaaaaaaa-0000-0000-0000-000000000001');
select public.report_client_error('1.0.0+1', 'android', 'E', 'm', 's')
  from generate_series(1, 80);
reset role;
select test.ok((select count(*) from public.client_errors) = 50,
  'laporan error dibatasi 50 per pengguna per hari');

-- -------------------------------------------------------------------- anon
set role anon;
select test.login(null);
select test.denied($$select * from public.stores$$, 'anon tidak bisa membaca toko');
select test.denied($$select public.is_admin()$$, 'anon tidak bisa memanggil is_admin');
select test.denied($$select public.consume_llm_quota(5)$$, 'anon tidak bisa memakai kuota AI');
select test.denied($$select public.delete_my_account()$$, 'anon tidak bisa menghapus akun');
select test.denied($$select public.report_client_error('1','x','e','m','s')$$,
  'anon tidak bisa melapor error');

-- ------------------------------------------------------------- hapus akun
reset role; set role authenticated;
select test.login('bbbbbbbb-0000-0000-0000-000000000002');
select public.delete_my_account();
reset role;
select test.ok((select count(*) from auth.users
  where id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'akun bob terhapus');
select test.ok((select count(*) from public.stores
  where owner_uid = 'bbbbbbbb-0000-0000-0000-000000000002') = 0,
  'toko bob ikut terhapus');
select test.ok((select count(*) from auth.users) = 2, 'akun lain tidak terpengaruh');

\o
\echo SEMUA UJI KEBIJAKAN LULUS
