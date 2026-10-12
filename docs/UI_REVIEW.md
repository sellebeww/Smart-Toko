# Review SmartToko — 6 Oktober 2026

Acuan desain: [Figma SmartToko](https://www.figma.com/design/EXgxTa7OZXrkHtvINldOyM/Untitled--Copy-?node-id=3-9376).
Logo diperbarui pada 16 Oktober 2026 dengan simbol toko, struk/Rp, dan mikrofon
untuk menjelaskan pencatatan keuangan lewat suara. PNG transparan disimpan di
`assets/brand/smarttoko-logo.png`; ikon Android/iOS, notifikasi, dan splash
diekspor dari berkas yang sama melalui `tool/export_brand.swift`.
Prompt dan cara ekspor ada di `assets/brand/README.md`.
Font Inter dibundel untuk penggunaan luring, beserta lisensi
OFL. Ikon SVG pada navigasi dan kartu berasal dari aset Figma.

## Hasil audit dan perbaikan

- Tema bersama mengikuti Figma: latar `#F7F7F1`, hijau `#176448`, teks
  `#20382E`, kartu hijau muda `#E8F2E9`, dan peringatan `#FFF1DF`.
- Beranda memuat penjualan, estimasi laba (omzet dikurangi biaya tercatat),
  stok menipis, aktivitas terbaru, dan progres pencatatan dari data toko aktif.
- Navigasi bawah menghubungkan Beranda, Transaksi, Stok, Laporan, dan Lainnya.
  Pilihan navigasi dinonaktifkan selama perekaman/pemrosesan suara.
- Halaman masuk memakai logo dan identitas baru. Onboarding dapat digulir,
  sehingga tombol Mulai tetap dapat dijangkau pada layar kecil atau teks besar.
- Ketik alami mengembalikan draf untuk diperiksa, bukan langsung disimpan.
  Sumber transaksi tetap Manual; teks hasil parse tetap disorot bila meragukan.
- Parser sekarang menerima `Rp200.000`, `Rp 200.000`, `Rp.200.000`, dan `rp200rb`.
- Ringkasan harian diperbarui saat melewati tengah malam atau aplikasi kembali
  aktif, termasuk data laporan, riwayat, dan progres.
- Cadangan dibaca dalam satu transaksi SQLite agar tabelnya konsisten.
  Pemulihan memeriksa versi, kelengkapan tabel, identitas baris, kepemilikan toko,
  dan relasi antarbaris sebelum menghapus data lokal. Cadangan rusak tidak lagi
  dapat dianggap sebagai cadangan kosong. Relasi ke data toko lain ditolak.
- Penghapusan cadangan mengambil seluruh halaman daftar Storage.
- SQL membatasi penulisan verifikasi ke empat nama berkas yang digunakan
  aplikasi dan kedalaman folder yang tepat. Nama cadangan juga harus berada
  langsung di folder pemilik. Status review `null` ditolak secara eksplisit.
- Ekspor laporan mencegah ketukan ganda dan menampilkan kegagalan secara ramah.

## Adaptasi desain ke aplikasi nyata

Mockup berisi nama, angka, foto menu, tugas harian, XP, dan pengingat contoh.
Implementasi menggunakan data toko aktif, tanpa menanamkan data contoh itu ke
aplikasi. Progres menghitung hari transaksi yang berurutan; belum ada pengingat
notifikasi terjadwal atau XP. Katalog tetap memakai menu/bahan yang benar-benar
tercatat; model produk belum memiliki foto. Grafik laporan memakai data periode
yang dipilih. Status bar dan area navigasi sistem ditangani Android/iOS.

Tombol Rekam dan Ketik tetap langsung dapat dijangkau di beranda, karena ini
alur utama aplikasi yang sudah ada. Keduanya berakhir di konfirmasi yang sama.
Desain diadaptasi ke Flutter dan fitur nyata; bukan salinan statis setiap layar
mockup.

## Validasi dan cara melihat hasil

Pemeriksaan pembaruan logo pada 16 Oktober 2026: `flutter analyze` tanpa masalah,
seluruh 401 tes Flutter lulus, dan APK debug berhasil dibangun. Dimensi serta
kanal alfa seluruh entri ikon/splash Android dan iOS sudah diperiksa; screenshot
dokumentasi diperbarui dari pengujian UI. Build iOS belum diuji karena Xcode
lengkap tidak tersedia. Tes SQL lokal belum dijalankan ulang karena Docker
daemon tidak aktif. Pemeriksaan ini tidak mencakup uji perangkat fisik.

```sh
flutter analyze
flutter test
flutter test test/ui/figma_layout_test.dart --dart-define=WRITE_UI_PREVIEWS=true
flutter build apk --debug
```

Pratinjau berada di `build/ui-previews/` (beranda, masuk, laporan, stok). Angka pada
pratinjau hanya fixture pengujian. Tes memeriksa layar 320 px dengan skala teks
1,0 dan 1,8, akses tombol onboarding, ketik alami, serta integritas cadangan.

## Batas pemeriksaan

SQL belum dijalankan pada server Supabase. Terapkan ulang `supabase/setup.sql`
melalui SQL Editor untuk mengaktifkan perubahan kebijakan, lalu jalankan uji
akun pemilik/admin sesuai README. Belum ada perangkat Android/iOS tersambung
untuk menguji mikrofon, kamera, OTP, unggahan, atau pemulihan cloud secara
menyeluruh. APK debug disediakan untuk pengujian perangkat, bukan rilis toko.

Fondasi aplikasi sudah layak untuk uji pengguna. Kesiapan produksi tetap perlu
hasil uji perangkat nyata dan alur Supabase; kelulusan tes lokal saja tidak
membuktikan semua integrasi tersebut sudah berfungsi.
