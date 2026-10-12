-- Uji sinkronisasi antar-HP dan karyawan. Dijalankan setelah 10_policies.sql
-- (fungsi test.* berasal dari sana).

\set ON_ERROR_STOP 1
\o /dev/null

reset role;
insert into auth.users (id, email) values
  ('0a000000-0000-0000-0000-00000000000a', 'pemilik@contoh.com'),
  ('0b000000-0000-0000-0000-00000000000b', 'karyawan@contoh.com'),
  ('0c000000-0000-0000-0000-00000000000c', 'orang.lain@contoh.com');

-- ------------------------------------------------------------- persiapan
set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
insert into public.stores (id, owner_uid, name, category) values
  ('5a000000-0000-0000-0000-00000000005a',
   '0a000000-0000-0000-0000-00000000000a', 'Warung Sinkron', 'warteg');

select test.denied($$select public.create_store_invite(
  '5a000000-0000-0000-0000-00000000005a')$$,
  'undangan butuh sinkronisasi menyala', '22023');
select test.denied($$select public.sync_push(
  '5a000000-0000-0000-0000-00000000005a', '[]'::jsonb)$$,
  'sinkron ditolak selama belum dinyalakan', '22023');
select test.denied($$update public.stores set sync_enabled = true
  where id = '5a000000-0000-0000-0000-00000000005a'$$,
  'kolom sync_enabled tidak bisa diubah langsung');
select public.set_store_sync('5a000000-0000-0000-0000-00000000005a', true);
select test.ok(public.store_role('5a000000-0000-0000-0000-00000000005a') = 'owner',
  'pemilik berperan owner');

-- Pemilik mengirim katalog bermodal dan satu penjualan.
select public.sync_push('5a000000-0000-0000-0000-00000000005a', $j$[
  {"table":"products","id":"p-ayam","data":{"id":"p-ayam","store_id":"5a000000-0000-0000-0000-00000000005a","name":"Ayam Geprek","cost_price":9000,"default_price":15000}},
  {"table":"transactions","id":"t-1","data":{"id":"t-1","store_id":"5a000000-0000-0000-0000-00000000005a","category":"penjualan","total_amount":30000}},
  {"table":"transaction_items","id":"i-1","data":{"id":"i-1","transaction_id":"t-1","product_id":"p-ayam","qty":2,"line_total":30000,"unit_cost":9000}}
]$j$::jsonb);
select test.ok((select count(*) from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0)) = 3, 'pemilik menarik barisnya');
select test.ok((select data->>'cost_price' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0) where row_id = 'p-ayam') = '9000',
  'pemilik melihat modal');
select test.denied($$select * from public.sync_rows$$, 'tabel sync_rows tertutup');

-- Baris milik toko lain ditolak.
select test.denied($$select public.sync_push('5a000000-0000-0000-0000-00000000005a',
  '[{"table":"contacts","id":"c-x","data":{"id":"c-x","store_id":"11111111-0000-0000-0000-000000000001"}}]'::jsonb)$$,
  'baris dengan store_id lain ditolak', '22023');
select test.denied($$select public.sync_push('5a000000-0000-0000-0000-00000000005a',
  '[{"table":"stores","id":"x","data":{}}]'::jsonb)$$,
  'tabel di luar daftar ditolak', '22023');

-- ---------------------------------------------------------------- undangan
create temp table invite_codes (code text);
grant all on invite_codes to authenticated;
insert into invite_codes select public.create_store_invite(
  '5a000000-0000-0000-0000-00000000005a');
select test.ok((select length(code) from invite_codes) = 10, 'kode undangan 10 karakter');
select test.denied($$select public.accept_store_invite((select code from invite_codes))$$,
  'pemilik tidak bisa bergabung ke tokonya sendiri', '22023');

reset role; set role authenticated;
select test.login('0b000000-0000-0000-0000-00000000000b');
select test.ok((select count(*) from public.stores
  where id = '5a000000-0000-0000-0000-00000000005a') = 0,
  'sebelum bergabung, toko tidak terlihat');
select test.denied($$select * from public.sync_pull('5a000000-0000-0000-0000-00000000005a', 0)$$,
  'bukan anggota tidak bisa menarik');
select test.ok(public.accept_store_invite('SALAH12345') is null,
  'kode salah ditolak');
-- Kode boleh diketik huruf kecil dan dengan tanda hubung.
select test.ok(public.accept_store_invite(
  (select lower(substr(code, 1, 5)) || '-' || lower(substr(code, 6)) from invite_codes)
) = '5a000000-0000-0000-0000-00000000005a', 'karyawan bergabung dengan kode');
select test.ok(public.accept_store_invite((select code from invite_codes)) is null,
  'kode hanya bisa dipakai sekali');
select test.ok(public.store_role('5a000000-0000-0000-0000-00000000005a') = 'staff',
  'karyawan berperan staff');
select test.ok((select count(*) from public.stores
  where id = '5a000000-0000-0000-0000-00000000005a') = 1,
  'setelah bergabung, toko terlihat');
select test.ok((select count(*) from public.my_staff_stores()) = 1,
  'toko muncul di daftar toko karyawan');
with changed as (
  update public.stores set name = 'Diambil alih'
  where id = '5a000000-0000-0000-0000-00000000005a' returning 1
) select test.ok((select count(*) from changed) = 0,
  'karyawan tidak bisa mengubah profil toko');

-- ------------------------------------------------- hak karyawan atas data
select test.ok((select data ? 'cost_price' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0) where row_id = 'p-ayam') = false,
  'modal disembunyikan dari karyawan');
select test.ok((select data ? 'unit_cost' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0) where row_id = 'i-1') = false,
  'modal per penjualan disembunyikan dari karyawan');

-- Penjualan oleh karyawan: modal diisi server dari katalog.
select public.sync_push('5a000000-0000-0000-0000-00000000005a', $j$[
  {"table":"transactions","id":"t-staff","data":{"id":"t-staff","store_id":"5a000000-0000-0000-0000-00000000005a","category":"penjualan","total_amount":15000}},
  {"table":"transaction_items","id":"i-staff","data":{"id":"i-staff","transaction_id":"t-staff","product_id":"p-ayam","qty":1,"line_total":15000,"unit_cost":1}},
  {"table":"products","id":"p-ayam","data":{"id":"p-ayam","store_id":"5a000000-0000-0000-0000-00000000005a","name":"Ayam Geprek","default_price":16000,"cost_price":1}}
]$j$::jsonb);

-- Karyawan mencoba menghapus penjualan pemilik.
create temp table cursor_before (v bigint);
grant all on cursor_before to authenticated;
insert into cursor_before select max(version) from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000);
select public.sync_push('5a000000-0000-0000-0000-00000000005a',
  '[{"table":"transactions","id":"t-1","deleted":true}]'::jsonb);
select test.ok((select deleted from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', (select v from cursor_before))
  where row_id = 't-1') = false,
  'hapus transaksi pemilik ditolak dan baris aslinya dikirim ulang');

select test.ok((select data->>'total_amount' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0) where row_id = 't-1') = '30000',
  'transaksi pemilik tetap utuh');

-- Karyawan menghapus transaksinya sendiri: boleh, barangnya ikut terhapus.
select public.sync_push('5a000000-0000-0000-0000-00000000005a', $j$[
  {"table":"transactions","id":"t-staff2","data":{"id":"t-staff2","store_id":"5a000000-0000-0000-0000-00000000005a","category":"penjualan"}},
  {"table":"transaction_items","id":"i-staff2","data":{"id":"i-staff2","transaction_id":"t-staff2","qty":1}},
  {"table":"debt_payments","id":"d-staff2","data":{"id":"d-staff2","store_id":"5a000000-0000-0000-0000-00000000005a","transaction_id":"t-staff2","amount":1000}}
]$j$::jsonb);
select public.sync_push('5a000000-0000-0000-0000-00000000005a',
  '[{"table":"transactions","id":"t-staff2","deleted":true}]'::jsonb);
select test.ok((select bool_and(deleted) from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000)
  where row_id in ('t-staff2', 'i-staff2', 'd-staff2')),
  'menghapus transaksi ikut menghapus barang dan pembayarannya');
select test.ok((select data from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000) where row_id = 't-staff2') is null,
  'baris terhapus tidak menyimpan isinya');

select test.denied($$select public.set_store_sync('5a000000-0000-0000-0000-00000000005a', false)$$,
  'karyawan tidak bisa mematikan sinkronisasi');
select test.denied($$select public.create_store_invite('5a000000-0000-0000-0000-00000000005a')$$,
  'karyawan tidak bisa membuat undangan');
select test.denied($$select * from public.store_member_list('5a000000-0000-0000-0000-00000000005a')$$,
  'karyawan tidak bisa melihat daftar anggota');
select test.denied($$select public.remove_store_member('5a000000-0000-0000-0000-00000000005a',
  '0b000000-0000-0000-0000-00000000000b')$$,
  'karyawan tidak bisa mengeluarkan anggota');

-- ---------------------------------------------------- dilihat dari pemilik
reset role; set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
select test.ok((select data->>'unit_cost' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000) where row_id = 'i-staff') = '9000',
  'penjualan karyawan memakai modal katalog, bukan isian karyawan');
select test.ok((select data->>'cost_price' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000) where row_id = 'p-ayam') = '9000',
  'karyawan tidak bisa mengubah modal');
select test.ok((select data->>'default_price' from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000) where row_id = 'p-ayam') = '16000',
  'karyawan boleh memperbarui harga jual');
select test.ok((select email from public.store_member_list(
  '5a000000-0000-0000-0000-00000000005a')) = 'karyawan@contoh.com',
  'pemilik melihat karyawannya');
select test.ok((
  select bool_and(a.version < b.version) from
    (select version, row_number() over (order by version) n
     from public.sync_pull('5a000000-0000-0000-0000-00000000005a', 0, 1000)) a
    join (select version, row_number() over (order by version) n
     from public.sync_pull('5a000000-0000-0000-0000-00000000005a', 0, 1000)) b
    on b.n = a.n + 1),
  'versi naik berurutan');
select test.ok((select count(*) from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 2)) = 2, 'batas jumlah tarikan berlaku');

-- --------------------------------------------------------- orang luar
reset role; set role authenticated;
select test.login('0c000000-0000-0000-0000-00000000000c');
select test.denied($$select public.sync_push('5a000000-0000-0000-0000-00000000005a', '[]'::jsonb)$$,
  'orang luar tidak bisa mengirim');
select test.ok((select count(*) from public.my_staff_stores()) = 0,
  'orang luar tidak punya toko karyawan');
do $$
begin
  for i in 1..20 loop
    perform public.accept_store_invite('TEBAK' || i);
  end loop;
end $$;
select test.denied($$select public.accept_store_invite('TEBAK21')$$,
  'tebakan kode dibatasi per hari', '54000');

-- Akun nomor HP (tanpa email) tampil dengan nomornya.
reset role;
insert into auth.users (id, phone) values
  ('0d000000-0000-0000-0000-00000000000d', '628123456789');
insert into public.store_members (store_id, user_id) values
  ('5a000000-0000-0000-0000-00000000005a', '0d000000-0000-0000-0000-00000000000d');
set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
select test.ok((select count(*) from public.store_member_list(
  '5a000000-0000-0000-0000-00000000005a') where email = '+628123456789') = 1,
  'karyawan dengan akun nomor HP tampil dengan nomornya');

-- --------------------------------------------- mengeluarkan karyawan
reset role; set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
select public.remove_store_member('5a000000-0000-0000-0000-00000000005a',
  '0b000000-0000-0000-0000-00000000000b');

reset role; set role authenticated;
select test.login('0b000000-0000-0000-0000-00000000000b');
select test.denied($$select * from public.sync_pull('5a000000-0000-0000-0000-00000000005a', 0)$$,
  'karyawan yang dikeluarkan tidak bisa menarik lagi');
select test.ok((select count(*) from public.stores
  where id = '5a000000-0000-0000-0000-00000000005a') = 0,
  'karyawan yang dikeluarkan tidak melihat toko lagi');

-- ------------------------------------------- mematikan sinkronisasi
reset role; set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
insert into invite_codes select public.create_store_invite(
  '5a000000-0000-0000-0000-00000000005a');
select public.set_store_sync('5a000000-0000-0000-0000-00000000005a', false);
select test.ok((select count(*) from public.sync_pull(
  '5a000000-0000-0000-0000-00000000005a', 0, 1000)) = 0,
  'mematikan sinkronisasi menghapus data toko di server');
reset role;
select test.ok((select count(*) from public.store_invites
  where store_id = '5a000000-0000-0000-0000-00000000005a') = 0,
  'undangan ikut dicabut');

-- ---------------------------------------------------- hapus akun pemilik
set role authenticated;
select test.login('0a000000-0000-0000-0000-00000000000a');
select public.set_store_sync('5a000000-0000-0000-0000-00000000005a', true);
select public.sync_push('5a000000-0000-0000-0000-00000000005a',
  '[{"table":"contacts","id":"c-1","data":{"id":"c-1"}}]'::jsonb);
select public.delete_my_account();
reset role;
select test.ok((select count(*) from public.sync_rows
  where store_id = '5a000000-0000-0000-0000-00000000005a') = 0,
  'hapus akun pemilik ikut menghapus data sinkron tokonya');

\o
\echo SEMUA UJI SINKRONISASI LULUS
