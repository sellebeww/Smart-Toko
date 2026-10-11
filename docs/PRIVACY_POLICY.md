# Kebijakan Privasi SmartToko

> **DRAF — belum berlaku.** Ini bahan awal yang disusun dari perilaku aplikasi
> yang sebenarnya. Sebelum dipublikasikan: isi bagian bertanda `[ISI]`, minta
> peninjauan hukum, lalu unggah sebagai halaman web publik dan berikan URL-nya
> ke build rilis (`--dart-define=PRIVACY_URL=...`) dan ke Play Console.

Terakhir diperbarui: `[ISI tanggal]`

SmartToko adalah aplikasi pencatatan keuangan warung. Dokumen ini menjelaskan
data apa yang diproses, untuk apa, dan bagaimana kamu mengendalikannya.

Pengelola: `[ISI nama/badan usaha]` — kontak: `[ISI email]`

## Data yang tersimpan di HP-mu

Transaksi, barang, stok, kontak pelanggan/supplier, dan profil toko disimpan
di basis data di HP-mu. Aplikasi tetap berfungsi tanpa internet. Data ini
tidak dikirim ke mana pun kecuali lewat fitur opsional di bawah.

## Data akun (wajib)

Untuk membuat akun kami menyimpan **alamat email** dan kata sandi (disimpan
dalam bentuk hash oleh penyedia autentikasi kami, Supabase) serta **profil
toko** (nama, kategori, alamat) di server.

## Fitur opsional — semuanya mati sampai kamu menyalakannya

| Fitur | Data yang dikirim | Tujuan | Ke mana |
|---|---|---|---|
| Cadangan cloud | Salinan transaksi, barang, stok, kontak, dan catatan utang/piutang toko | Memulihkan data bila HP hilang atau diganti | Server SmartToko (Supabase). Hanya akunmu yang bisa membukanya |
| Verifikasi toko | Foto KTP, foto toko, selfie memegang KTP, dan NIB bila ada | Memastikan toko nyata | Server SmartToko. Hanya kamu dan admin peninjau yang bisa membukanya. Tidak dipakai untuk tujuan lain |
| Bantuan AI | Kalimat yang kamu ucapkan, hanya saat pengurai di HP gagal | Mengurai ucapan sulit menjadi draf transaksi | Server SmartToko lalu Anthropic (penyedia model AI). Hasilnya tetap kamu periksa sebelum disimpan |
| Laporan error | Jenis error, pesan dan jejak yang dipotong (email dan angka panjang dibuang), versi aplikasi, jenis HP | Memperbaiki bug | Server SmartToko. Tanpa data transaksi, nama, atau kontak |

Kamu bisa mematikan tiap fitur di **Pengaturan** kapan saja.

## Kunci PIN

PIN hanya tersimpan di HP-mu dalam bentuk hash; tidak pernah dikirim ke
server. Bila lupa PIN, keluar dari akun menghapus kunci, dan datamu terbuka
lagi setelah masuk dengan email dan kata sandi.

## Pengingat tagihan

Pesan pengingat disiapkan di HP-mu dan dikirim lewat WhatsApp atau aplikasi
lain yang kamu pilih, hanya saat kamu menekan kirim. SmartToko tidak mengirim
pesan sendiri dan tidak menyimpan percakapan itu.

## Pengenalan suara

Saat kamu merekam transaksi, pengenalan ucapan dilakukan oleh layanan bawaan
sistem HP-mu (di Android biasanya layanan suara Google, di iOS layanan ucapan
Apple), yang dapat memprosesnya di server penyedia tersebut. Itu berada di
luar kendali SmartToko dan tunduk pada kebijakan penyedianya.

## Penyimpanan dan penghapusan

- Data di server disimpan selama akunmu ada.
- **Hapus akun** di Pengaturan menghapus akun, profil toko, berkas verifikasi,
  cadangan, dan data pemakaian dari server, lalu membersihkan data di HP.
- Laporan error `[ISI masa simpan, mis. 90 hari]`.

## Keamanan

Akses data di server dibatasi per akun dengan aturan akses tingkat baris
(Row Level Security). Berkas verifikasi disimpan di penyimpanan privat dan
hanya dapat dibuka lewat tautan sementara oleh admin peninjau.

## Hakmu

Kamu dapat mengakses, memperbaiki, atau menghapus datamu. Penghapusan akun
bisa dilakukan sendiri dari aplikasi; untuk permintaan lain hubungi
`[ISI email]`.

## Anak-anak

SmartToko ditujukan untuk pemilik usaha dewasa dan tidak sengaja
mengumpulkan data anak-anak.

## Perubahan

Perubahan kebijakan ini akan diumumkan di aplikasi atau lewat email sebelum
berlaku.
