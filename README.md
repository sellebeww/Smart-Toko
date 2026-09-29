# SmartToko

Aplikasi Flutter untuk mencatat pemasukan dan pengeluaran toko lewat suara atau
ketikan. Setiap draf diperiksa pengguna sebelum disimpan ke SQLite di perangkat.
Akun dan profil multi-toko disimpan di Firebase; verifikasi toko bersifat opsional.

## Menjalankan

Gunakan Flutter yang menyertakan Dart sesuai `pubspec.yaml` (`^3.13.4`).
Konfigurasi Firebase aplikasi berada di `lib/firebase_options.dart` dan konfigurasi
platform Android. Aktifkan penyedia Email/Password di Firebase Authentication,
serta Firestore dan Storage pada proyek yang digunakan.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5554
```

Pilih ID perangkat dari `flutter devices` bila berbeda. Android adalah platform
yang diuji untuk build aplikasi ini. Pengaturan izin kamera, galeri, mikrofon, dan
pengenalan ucapan iOS sudah disertakan; build dan integrasi Firebase iOS tetap
perlu divalidasi pada perangkat Apple yang dikonfigurasi.

## Alur yang tersedia

- Registrasi dan masuk dengan email/kata sandi; tautan lupa kata sandi via email.
- Tambah dan pilih toko; pilihan terakhir diingat terpisah untuk setiap akun.
- Rekam transaksi atau ketik manual, periksa rincian, lalu simpan.
- Ringkasan pemasukan/pengeluaran dan transaksi hari ini dari penyimpanan lokal.
- Persetujuan verifikasi, foto KTP/toko/selfie, dan NIB opsional; progres unggah,
  pembatasan ukuran foto, serta penghapusan salinan sementara saat selesai/batal.
- Panel simulasi admin untuk perubahan status pengajuan.

Login menggunakan nomor HP dan kata sandi belum tersedia. Autentikasi yang
terpasang saat ini menggunakan email dan kata sandi.

## Pengujian manual

1. Masuk, tambah toko, ganti toko, tutup/buka aplikasi, dan pastikan toko terakhir
   dipulihkan. Keluar lalu masuk akun lain; toko aktif tidak boleh terbawa.
2. Buka lupa kata sandi; coba email tidak valid, koneksi gagal, dan email akun uji.
   Pengiriman email sungguhan membutuhkan Firebase yang dapat dijangkau.
3. Rekam lalu segera berhenti; coba rekaman kosong, ketik saat sedang merekam,
   serta hasil suara final. Satu sesi hanya boleh membuka satu draf konfirmasi.
4. Di draf, jumlah nol harus ditolak. Kegagalan simpan harus mempertahankan isian
   untuk dicoba lagi. Pastikan transaksi masuk ke toko yang dipilih.
5. Buka persetujuan verifikasi di layar kecil/huruf besar. Semua teks, kotak
   persetujuan, dan tombol lanjut harus dapat dijangkau dengan menggulir.
6. Dengan data uji, coba menolak izin kamera, memilih/mengganti foto, membatalkan,
   memutus koneksi, dan mengirim pengajuan. Periksa status di Pengaturan.

Tes otomatis memakai pengganti layanan untuk alur suara dan reset kata sandi;
kelulusannya bukan bukti pengiriman email atau unggah foto ke Firebase sungguhan.

## Batasan layanan dan data

`firestore.rules` dan panel admin saat ini sengaja mengikuti simulasi demo:
semua akun yang login dapat membaca profil toko dan mengubah status verifikasi.
Ini **belum merupakan otorisasi admin untuk produksi**. Sebelum rilis publik,
pasang role admin yang diverifikasi server dan batasi perubahan field/status
pada rules. Storage membatasi berkas verifikasi ke UID pemilik, gambar, dan
ukuran di bawah 10 MB. Perubahan file rules lokal tidak otomatis terbit ke Firebase.

Transaksi lokal tidak otomatis tersedia di perangkat lain. Infrastruktur antrean
sinkronisasi tersedia, tetapi target server transaksi masih perlu diimplementasikan.
Foto verifikasi tersimpan di Firebase Storage; foto asli di galeri tidak dihapus.
Jika pengajuan berhenti di tengah, sebagian unggahan mungkin sudah ada di server.
Panel demo tidak menampilkan kembali dokumen identitas.

Keputusan arsitektur awal ada di `DESIGN_DECISIONS.md`; bagian status implementasi
Firebase/verifikasi di dokumen tersebut mendahului fitur akun dan unggah saat ini.
