# Validasi perbaikan — 29 September 2026

## Hasil

- Pemeriksaan awal: `flutter analyze` bersih dan 92 tes lama lulus.
- Setelah perbaikan utama: seluruh 110 tes lulus dalam satu eksekusi
  `flutter test --reporter compact`.
- Setelah temuan terakhir pada target sinkronisasi: satu tes regresi tambahan
  `test/sync/unconfigured_target_test.dart` lulus dan analyzer kembali bersih.
  Total kasus yang sudah lulus: 111.
- APK debug berhasil dibangun dan aplikasi berjalan pada emulator Android 17
  (`emulator-5554`). Layar utama memuat toko yang sudah ada di cache dan formulir
  transaksi manual dapat dibuka. Pengujian tampilan tidak menyimpan transaksi baru.

## Regresi yang dijaga

- Reset kata sandi: validasi email, pemangkasan spasi, pesan netral untuk akun
  tidak ditemukan, kegagalan jaringan dan mencoba kembali, serta navigasi keluar
  ketika permintaan belum selesai.
- Suara: ketukan rekam ganda, hasil final bersamaan dengan stop, stream berakhir
  dengan hasil parsial, tanpa ucapan, hasil terlambat setelah cancel/reset,
  kegagalan parser dan stop.
- Toko: pilihan terakhir terpisah per akun; pemilihan yang sedang menunggu
  penyimpanan tidak boleh mengaktifkan toko milik akun sebelumnya.
- Konfirmasi: jumlah nol ditolak; isian tidak hilang ketika penyimpanan gagal.
- Persetujuan: layar 320 × 568 dengan skala teks 1,4 tetap dapat digulir ke tombol.
- Sinkronisasi: target bawaan tidak memberikan pengakuan berhasil tanpa backend.

## Hambatan yang ditemukan di emulator

SDK Firestore melaporkan `PERMISSION_DENIED` dengan keterangan bahwa Cloud
Firestore API belum pernah digunakan atau dinonaktifkan pada proyek
`smart-toko-app`. Dokumen cache masih dapat tampil, tetapi hal ini bukan bukti
bahwa penulisan profil atau pengajuan verifikasi diterima server.

Pengiriman email reset nyata, unggahan identitas, dan persetujuan server belum
diuji menyeluruh. Rules lokal tidak diterbitkan ke Firebase dalam pekerjaan ini.
Panel admin dan Firestore rules masih menggunakan model simulasi demo, bukan
role admin produksi. Login nomor HP/kata sandi belum tersedia.

Build Android juga mengeluarkan peringatan kompatibilitas Kotlin Gradle Plugin
untuk versi Flutter mendatang pada plugin Firebase; build saat ini berhasil.
Build iOS dan pengenalan ucapan menggunakan mikrofon perangkat nyata belum diuji.

## Lokasi hasil

APK debug: `build/app/outputs/flutter-apk/app-debug.apk`.
Petunjuk menjalankan dan skenario uji manual: `README.md`.
