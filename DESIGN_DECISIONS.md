# Keputusan Arsitektur — SmartToko

Dokumen ini menjelaskan alasan teknis di balik rancangan fitur pencatatan
transaksi berbasis suara pada SmartToko. Fokusnya bukan pada cara kerja kode
(itu bisa dibaca dari kodenya), melainkan pada **mengapa** rancangan ini dipilih
dan **apa yang dikorbankan** oleh tiap pilihan.

---

## 1. Masalah dan Batasan

SmartToko menyasar satu situasi spesifik: pemilik warung yang tangannya sedang
sibuk atau kotor dan tidak praktis memegang layar. Nilai jualnya adalah
**kecepatan mencatat tanpa menyentuh layar**, bukan kelengkapan pembukuan.

Tujuh risiko diidentifikasi di awal. Yang penting untuk dicatat: ketujuhnya
bukan bug yang bisa ditambal belakangan, melainkan konsekuensi dari pilihan
arsitektur. Kalau mitigasinya hanya diserahkan pada disiplin pengembang
("nanti jangan lupa minta konfirmasi"), cepat atau lambat akan bocor.

Karena itu rancangan ini menerjemahkan ketujuh risiko menjadi **tiga jaminan
struktural** yang ditegakkan oleh tipe data dan titik-sempit (*chokepoint*),
bukan oleh konvensi.

| Jaminan | Ditegakkan oleh | Menutup risiko |
|---|---|---|
| Tidak ada jalur dari audio ke basis data yang melewati manusia | `TransactionRepository.save()` hanya menerima `ConfirmedDraft` | Akurasi di lingkungan bising |
| Tidak ada data keluar perangkat tanpa sakelar eksplisit | Semua payload melewati `SyncPayloadBuilder`, dijaga pengujian | Kepatuhan UU PDP, kekhawatiran pengawasan |
| Suara adalah salah satu jalur masukan, bukan satu-satunya | Jalur suara dan ketik manual menghasilkan tipe yang sama dan memakai layar yang sama | Ketergantungan pada internet/STT |

---

## 2. Yang Sengaja TIDAK Dibangun

Pembatasan lingkup adalah keputusan arsitektur, bukan kekurangan.

- **Bukan aplikasi pembukuan lengkap.** Tanpa utang/piutang, faktur,
  multi-pengguna per toko, atau pelaporan pajak. Bersaing fitur-lawan-fitur
  dengan BukuWarung/BukuKas adalah pertarungan yang tidak mungkin dimenangkan
  dan akan mengaburkan satu-satunya keunggulan yang dimiliki.
- **Katalog, stok, dan kontak tumbuh dari transaksi**, bukan diisi terpisah:
  barang yang dijual menjadi menu, barang yang dibeli menjadi bahan dan
  menambah stok. Pengguna tidak dipaksa "mengatur toko" sebelum mencatat.
- **Laporan dibuat sederhana**: total per kategori, menu terlaris, dan export
  Excel. Cukup untuk menjawab "hari ini dapat berapa" dan "uangnya ke mana".
- **Tanpa *wake word* selalu-aktif.** Secara teknis memungkinkan, tetapi
  mikrofon yang menyala terus-menerus boros baterai dan — lebih penting —
  memperkuat persis kecurigaan yang ingin dihindari. Ditolak secara sadar.
- **Tanpa layanan latar belakang.** Pencadangan hanya berjalan saat aplikasi
  dibuka atau sesaat ketika ditinggalkan. Ini memang membuat data kurang segar, tetapi memungkinkan pernyataan
  jujur kepada pengguna: aplikasi ini tidak melakukan apa pun saat tidak dibuka.

---

## 3. Pilihan Teknologi

### 3.1 Manajemen state: Riverpod

**Alasan utama: banyak logika aplikasi ini hidup di luar widget tree.** Callback
aliran STT, pemicu pencadangan, dan pemantau konektivitas semuanya
membutuhkan akses dependensi tanpa `BuildContext`. Provider mensyaratkan
`BuildContext` untuk `read`; Riverpod tidak.

Alasan pendukung:
- `AsyncValue` memodelkan triad memuat/galat/data secara bawaan. Jalur STT dan
  LLM memang rawan gagal, sehingga kondisi "gagal → tawarkan manual" menjadi
  *state* bertipe, bukan tumpukan variabel boolean yang mudah tidak sinkron.
- `ProviderContainer` dan mekanisme *override* membuat parser serta layanan
  cadangan dapat diuji tanpa UI. Ini penting karena parser adalah komponen
  paling rapuh dan akan sering diiterasi.

**Yang dikorbankan.** Riverpod punya kurva belajar lebih curam daripada
Provider. Mitigasinya: penggunaan dibatasi pada `Notifier`, `AsyncNotifier`, dan
`Provider` biasa, **tanpa *code generation***, sehingga kode tetap terbaca
sebagai Dart biasa.

### 3.2 Basis data lokal: sqflite

Basis data lokal adalah **sumber kebenaran**. Cloud, bila diaktifkan, hanyalah
cermin — bukan sebaliknya.

Alasan memilih sqflite dibanding Hive:

1. **Atomisitas.** Penulisan transaksi, barangnya, katalog, dan pergerakan
   stoknya harus menjadi satu kesatuan; begitu juga pemulihan cadangan yang
   mengganti seluruh data toko. Bila aplikasi mati di tengah jalan, hasilnya
   tidak boleh setengah jadi. SQLite menyediakan transaksi sungguhan; Hive
   tidak menjaminnya antar-*box*.
2. **Agregasi.** "Total hari ini" adalah `SUM ... WHERE` di SQL dan tetap murah
   ketika baris menumpuk. Di Hive, agregasi berarti memuat seluruh data ke
   memori lalu melipatnya di Dart.
3. **Keterbacaan skema.** Skema eksplisit dengan migrasi bernomor lebih mudah
   dipertanggungjawabkan daripada penyimpanan kunci-nilai yang tidak
   berstruktur.

**Yang dikorbankan.** Migrasi harus ditulis tangan. Mitigasinya adalah daftar
migrasi bernomor sejak versi 1 (`lib/core/db/migrations.dart`) dengan aturan
tegas: migrasi yang sudah dirilis tidak pernah diubah isinya, karena perangkat
pengguna sudah terlanjur menjalankannya.

sqflite dipakai langsung (tanpa Drift) agar SQL-nya terlihat dan permukaan
dependensi tetap tipis. Konsekuensinya tidak ada pemeriksaan SQL saat kompilasi;
ini diimbangi dengan menempatkan seluruh SQL di kelas DAO yang diuji.

---

## 4. Model Data

Lokal (SQLite, sumber kebenaran catatan):

```
stores(id, owner_uid, name, category, address, verification_status, …)  -- salinan dari server
transactions(id, store_id, direction, category, occurred_at, source, total_amount, contact_id, …)
transaction_items(id, transaction_id, name, qty, unit_price, line_total, unit, product_id, …)
products(id, store_id, kind, name, name_key, unit, default_price, …)
stock_movements(id, store_id, product_id, qty_delta, reason, transaction_item_id, …)
contacts(id, store_id, kind, name, location, phone, note, …)
parse_failures(id, transcript, stt_confidence, parser_version, reason, …)
consents(id, kind, granted, consent_text_version, granted_at, revoked_at)
app_settings(key, value)
```

Server (Supabase, lihat `supabase/setup.sql`):

```
stores                 profil toko + status verifikasi (sumber kebenaran profil)
admins                 akun peninjau verifikasi
verification_reviews   jejak audit setiap keputusan admin
llm_usage              kuota harian bantuan AI per akun
storage: verifications/{uid}/{storeId}/*.jpg   foto KTP, toko, selfie, NIB
storage: backups/{uid}/{storeId}.json.gz       cadangan utuh per toko
```

Dua keputusan yang perlu disorot:

- **`transaction_items` dibuat multi-barang sejak awal**, meskipun parser versi
  pertama baru menangani kasus sederhana. Memigrasikan model satu-barang menjadi
  multi-barang di kemudian hari jauh lebih mahal daripada menyiapkan skemanya
  dari awal. Skema dibuat fleksibel lebih dulu; kemampuan parser menyusul.
- **`consents.consent_text_version` menyimpan versi teks persetujuan**, bukan
  sekadar nilai boolean. Untuk keperluan UU PDP, yang perlu dibuktikan bukan
  hanya "pengguna setuju", melainkan "pengguna setuju terhadap kalimat yang
  mana". Teks persetujuan akan berubah seiring waktu; catatannya tidak boleh
  ikut berubah.

---

## 5. Pipeline Suara

```
Tombol rekam
   └─ SpeechService          luring dicoba lebih dulu, daring sebagai cadangan
        └─ ParserPipeline    aturan cepat, LLM hanya bila mentok
             └─ Layar konfirmasi   WAJIB
                  └─ Repository    tulis lokal (cadangan menyusul bila dinyalakan)
```

### 5.1 Model keyakinan dan satu jebakan penting

Keyakinan tiap field dihitung sebagai `keyakinan STT × kekuatan kecocokan
aturan`, lalu dipetakan ke tiga pita:

| Nilai | Perlakuan |
|---|---|
| ≥ 0,80 | tampil normal |
| 0,50 – 0,79 | disorot, diberi label "cek lagi" |
| < 0,50 | nilainya dikosongkan, fokus diarahkan ke sana |

**Jebakan yang ditemukan saat implementasi.** Paket `speech_to_text` memakai
nilai **-1** sebagai penanda "keyakinan tidak tersedia", dan sebagian mesin
pengenal Android justru melaporkan **0.0** meski hasilnya sudah final.
Memperlakukan keduanya sebagai "keyakinan sangat rendah" akan menyebabkan
**seluruh field selalu kosong** di perangkat-perangkat tersebut, dan fitur suara
menjadi tidak berguna sama sekali.

Karena itu ketidaktahuan dimodelkan secara eksplisit sebagai
`Confidence.unknown()` — berbeda dari keyakinan rendah — dan dipetakan ke pita
"perlu dicek", bukan "buruk". Keputusan ini dikunci di tingkat tipe data
(`lib/core/confidence.dart`) dan dijaga oleh pengujian.

### 5.2 Arah transaksi tidak pernah ditebak

Bila kata arah ("jual", "beli", …) tidak terdengar, field arah dibiarkan
**kosong** dan pengguna wajib memilih sendiri. Alternatifnya — memilihkan
"masuk" karena penjualan lebih sering terjadi — berisiko mencatat pengeluaran
sebagai pemasukan, dan pengguna yang terburu-buru tidak akan menyadarinya.
Kesalahan diam-diam lebih berbahaya daripada satu ketukan tambahan.

---

## 6. Parser

Modul `lib/features/voice_parser/` ditulis sebagai **Dart murni tanpa impor
Flutter**, agar dapat diuji dengan cepat dan kelak mudah diangkat menjadi paket
terpisah.

### 6.1 Dua lapis

1. **Berbasis aturan** — cepat, deterministik, berjalan luring. Menangani pola
   umum dan memberi skor kepercayaan per slot.
2. **Berbantuan LLM** — hanya dipanggil bila lapisan pertama benar-benar mentok
   (tidak ada barang dikenali, ada token tak terpetakan, atau arah tidak
   tersebut) **dan** perangkat sedang daring **dan** pengguna sudah
   mengaktifkannya.

Eskalasi sengaja tidak dipicu oleh sekadar "agak ragu". Hasil yang cuma berpita
"perlu dicek" tetap ditampilkan apa adanya; memanggil LLM untuk itu memboroskan
waktu tunggu pengguna dan mengirim transkrip keluar perangkat tanpa perlu.

Saat menggabungkan kedua hasil, **hasil aturan yang sudah berkeyakinan baik
tidak pernah ditimpa oleh LLM**. Dengan begitu perbaikan aturan selalu
memberikan hasil yang dapat diprediksi.

### 6.2 Angka Bahasa Indonesia

Bagian tersulit adalah normalisasi sebutan angka. Algoritmanya memisahkan tiga
akumulator — `pending` (angka kecil yang baru dibaca), `section` (nilai di bawah
seribu), dan `total` (hasil yang sudah melewati batas ribu/juta). Pemisahan ini
yang membuat *"seratus lima puluh ribu"* terbaca 150.000 dan bukan 1.050.000.

Ditangani: `"dua puluh lima ribu"`, `"seratus lima puluh ribu"`, `"setengah
juta"`, `"dua setengah juta"`, `"25rb"`, `"25k"`, `"25.000"`, `"2,5jt"`, serta
pemisahan dua angka berurutan menjadi kuantitas dan harga
(*"jual indomie dua lima ribu"* → 2 unit @ Rp5.000).

### 6.3 Catatan kegagalan

Setiap ucapan yang gagal atau meragukan dicatat ke tabel `parse_failures`
beserta versi parser yang menanganinya. Ini satu-satunya cara aturan dapat
diperbaiki berdasarkan bukti, bukan dugaan. Catatan ini **lokal**; mengirimkannya
keluar memerlukan persetujuan tersendiri karena transkrip dapat memuat informasi
pribadi.

Korpus pengujian (`test/voice_parser/rule_parser_corpus_test.dart`) menjadikan
perbaikan parser terukur: setiap ucapan yang pernah salah diurai ditambahkan
sebagai kasus uji **sebelum** aturannya diperbaiki.

---

## 7. Privasi dan Kepercayaan

### 7.1 Gagal-tertutup

Seluruh sakelar privasi bernilai `false` ketika barisnya tidak ada di basis data
(`SettingsDao.getFlag`). Basis data yang baru dibuat, rusak sebagian, atau gagal
dimigrasi karena itu tidak akan pernah berakhir dengan pencadangan atau bantuan
AI menyala tanpa sepengetahuan pengguna.

### 7.2 Titik-sempit payload

Semua catatan yang keluar perangkat — termasuk isi cadangan — melewati
`SyncPayloadBuilder`. Penyaringan
field identitas dilakukan sebagai langkah **terakhir dan tanpa syarat**, secara
rekursif termasuk ke dalam peta dan daftar bersarang. Artinya penambahan entitas
baru di kemudian hari tidak dapat membocorkan data KTP hanya karena penulisnya
lupa.

Berkas `test/sync/payload_redaction_test.dart` berfungsi sebagai penjaga: bila
salah satu pengujian di sana gagal, berarti ada jalur yang dapat mengirim data
identitas tanpa persetujuan.

### 7.3 Dua sakelar terpisah, bukan satu

Pencadangan dan bantuan AI sama-sama mengirim data keluar perangkat, tetapi
tujuan, penerima, dan isinya berbeda:

- Pencadangan mengirim **catatan toko** ke penyimpanan milik akun pengguna.
- Bantuan AI mengirim **kalimat yang diucapkan pengguna** ke server aplikasi
  lalu ke layanan AI pihak ketiga.

Menggabungkan keduanya di bawah satu sakelar akan membuat persetujuan menjadi
tidak bermakna. Karena itu keduanya dipisah, masing-masing dengan penjelasan
spesifik tentang apa yang terjadi bila dinyalakan.

Pemeriksaan sakelar bantuan AI dilakukan **pada saat pemanggilan**, bukan saat
perakitan objek (`GatedLlmParser`). Bila diperiksa sekali di awal, mematikan
sakelar tidak akan berpengaruh sampai aplikasi dimulai ulang — dan selama itu
transkrip masih terkirim.

### 7.4 Verifikasi toko bertahap

Toko berstatus `unverified` secara bawaan dan **berfungsi penuh**. Verifikasi
hanya menambahkan lencana. Ini yang menjaga agar pengumpulan data KTP benar-benar
opsional, bukan syarat terselubung untuk memakai aplikasi.

Pengamannya ada di server, bukan di aplikasi:

- Klien hanya punya hak tulis ke kolom `name`, `category`, `address` tabel
  `stores` (hak kolom Postgres). Pemilik tidak bisa menandai tokonya sendiri
  terverifikasi, apa pun yang dikirim aplikasinya.
- Pengajuan lewat `submit_store_verification`, yang memeriksa kepemilikan,
  status, dan keberadaan tiga foto wajib di Storage.
- Keputusan lewat `review_store_verification`, yang hanya menerima akun di
  tabel `admins`, hanya untuk pengajuan yang masih menunggu, dan mencatat
  setiap keputusan di `verification_reviews`.
- Foto hanya bisa dibaca pemiliknya dan admin, dan tidak bisa ditukar setelah
  diajukan atau disetujui.
- Teks persetujuan yang disetujui dicatat versinya (`identity_consent_version`).
- Salinan foto di HP dihapus begitu layar unggah ditutup.

### 7.5 Kunci API di server

Bantuan AI lewat Edge Function `parse-transaction`. Kunci Anthropic hanya ada
sebagai *secret* di Supabase; aplikasi tidak pernah memegangnya. Fungsi itu:

- hanya menerima **transkrip** (maks. 500 karakter), bukan permintaan bebas ke
  model, jadi tidak bisa disalahgunakan sebagai *proxy* umum;
- mewajibkan JWT pengguna yang login;
- membatasi pemakaian per akun per hari (`consume_llm_quota`, bawaan 200);
- memegang prompt dan skema keluaran, sehingga perbaikan prompt tidak perlu
  rilis aplikasi baru.

Model yang dipakai `claude-opus-5-5` dengan *effort* rendah dan keluaran
terstruktur (`json_schema`), plus `fallbacks: "default"` agar permintaan
yang ditolak pengaman model dicoba ulang otomatis di model lain.

### 7.6 Keyakinan hasil LLM dibatasi

Hasil dari LLM dibatasi maksimum **0,79**, tepat di bawah ambang "baik", sehingga
selalu jatuh ke pita "perlu dicek". Alasannya: LLM baru dipanggil justru ketika
parser deterministik sudah ragu, dan angka keyakinan yang dilaporkan sendiri oleh
model bukan ukuran yang terkalibrasi. Menampilkannya sebagai "yakin" akan
menyesatkan pengguna.

---

## 8. Cadangan Cloud

Rancangan awal memakai antrean sinkron per transaksi. Rancangan itu diganti
**cadangan utuh per toko** karena dua alasan:

1. **Pemulihan harus lengkap.** Antrean per transaksi hanya mencakup
   transaksi; barang, stok, dan kontak tertinggal. Pemilik yang ganti HP butuh
   *semuanya* kembali dalam keadaan konsisten.
2. **Lebih sedikit yang bisa salah.** Tidak ada urutan kiriman, konflik, atau
   baris yatim di server. Satu berkas, satu transaksi basis data saat
   dipulihkan.

Cara kerjanya:

- Isi toko (lima tabel) dibentuk menjadi JSON, disaring `SyncPayloadBuilder`,
  dikompres gzip, lalu diunggah ke `backups/{uid}/{storeId}.json.gz`.
- Cadangan otomatis hanya berjalan bila sakelarnya menyala, dan hanya bila
  **sidik data** (jumlah baris, waktu ubah terakhir, total) berubah sejak
  cadangan terakhir. Saat aplikasi dibuka ulang ada jeda minimum 10 menit;
  saat aplikasi ditinggalkan, cadangan langsung dibuat bila ada perubahan.
- Toko yang masih kosong dan belum pernah dicadangkan **tidak pernah**
  mengunggah, supaya HP baru tidak menimpa cadangan lama sebelum sempat
  dipulihkan. Layar utama menawarkan pemulihan dalam keadaan itu.
- Pemulihan menolak berkas dari toko lain, berkas rusak, dan cadangan dari
  versi skema yang lebih baru dari aplikasi.

**Yang dikorbankan.** Setiap cadangan mengunggah seluruh isi toko, bukan
selisihnya. Untuk skala warung (puluhan ribu baris per tahun, sekitar 1 MB
setelah dikompres) ini murah, tetapi tidak cocok untuk toko yang sangat besar.
Field identitas (`recorded_by`) tidak ikut cadangan, jadi keterangan "dicatat
oleh" kosong untuk transaksi hasil pemulihan.

Profil toko punya salinan lokal (`StoreCache`). Aplikasi menampilkan salinan
itu lebih dulu lalu menggantinya dengan data server, sehingga tetap bisa
dibuka dan dipakai mencatat saat luring.

Catatan teknis: `connectivity_plus` melaporkan ada-tidaknya antarmuka jaringan,
bukan keterjangkauan internet. WiFi warung yang terhubung tetapi tagihannya belum
dibayar tetap dilaporkan "online". Status tersebut karena itu hanya dipakai untuk
memutuskan apakah **layak mencoba**; kepastian datang dari hasil percobaannya
sendiri, dan cadangan yang gagal cukup dicoba lagi pada kesempatan berikutnya.

---

## 9. Batasan yang Perlu Diakui

Dokumen ini akan kehilangan gunanya kalau hanya memuat klaim keberhasilan.

1. **Jaminan "tidak ada penyimpanan tanpa konfirmasi" bertumpu pada satu fungsi.**
   Privasi Dart berlaku per-pustaka, sehingga konstruktor `ConfirmedDraft` memang
   tidak dapat dijangkau dari luar berkasnya, tetapi fungsi `confirmDraftByUser`
   tetap dapat dipanggil dari mana saja. Jaminannya karena itu adalah
   "satu titik-sempit bernama jelas + pengujian", bukan jaminan kompilator penuh.
2. **Pengenalan suara luring bergantung pada model bahasa yang terpasang di
   perangkat**, dan aplikasi tidak dapat memasangnya sendiri. Yang bisa dilakukan
   hanyalah mendeteksi ketiadaannya dan beralih ke masukan manual.
3. **Parser belum diuji dengan rekaman nyata di lingkungan bising.** Korpus saat
   ini berisi kalimat yang disusun manual. Pengujian lapangan diperlukan sebelum
   klaim akurasi apa pun dibuat.
4. **Penangkapan notifikasi QRIS belum diimplementasikan** — baru dirancang
   (§10). Menu yang belum berfungsi sengaja tidak ditampilkan di aplikasi.
5. **Login nomor HP belum tersedia.** Butuh penyedia SMS berbayar di Supabase;
   autentikasi saat ini email + kata sandi dengan kode OTP lewat email.
6. **Keyakinan gabungan (`STT × aturan`) adalah heuristik**, bukan probabilitas
   terkalibrasi. Ambang 0,80 dan 0,50 ditetapkan berdasarkan pertimbangan, dan
   perlu ditala ulang setelah ada data pemakaian nyata.

---

## 10. Rancangan Fitur QRIS (belum diimplementasikan)

Dicatat di sini agar rancangannya tidak hilang:

- Fitur **mati secara bawaan** dan hanya menyala atas tindakan eksplisit
  pengguna.
- Sebelum dialog izin sistem muncul, ditampilkan layar penjelasan yang menyebut
  secara spesifik: notifikasi apa yang dibaca, apa yang disimpan, dan bagaimana
  mematikannya.
- Hanya membaca notifikasi dari **daftar-izin nama paket** aplikasi pembayaran
  yang dipilih pengguna — bukan seluruh notifikasi perangkat.
- Hasil tangkapan menjadi **draf yang tetap wajib dikonfirmasi**, mengikuti
  aturan yang sama dengan jalur suara.
- Indikator terlihat saat fitur aktif, dan dapat dimatikan dengan satu ketukan.

Tanpa rangkaian ini, fitur yang membaca notifikasi wajar dicurigai sebagai
*spyware* — dan kecurigaan itu, sekali muncul, merusak kepercayaan pada seluruh
aplikasi.

---

## 11. Strategi Pengujian

| Berkas | Yang dijaga |
|---|---|
| `test/voice_parser/indonesian_number_test.dart` | Ketepatan pembacaan angka |
| `test/voice_parser/rule_parser_corpus_test.dart` | Korpus regresi parser |
| `test/voice_parser/cloud_llm_parser_test.dart` | Pemetaan hasil AI, batas keyakinan, kegagalan tidak melempar |
| `test/sync/payload_redaction_test.dart` | Data identitas tidak pernah lolos |
| `test/backup/backup_service_test.dart` | Sakelar cadangan, tidak menimpa cadangan lama, pemulihan utuh |
| `test/stores/store_cache_test.dart` | Toko tetap terbuka saat luring, transaksi tidak ikut terhapus |
| `test/db/transaction_repository_test.dart` | Atomisitas, gerbang konfirmasi |
| `test/db/catalog_stock_test.dart` | Katalog, stok, migrasi dari v1 |
| `test/auth/reset_password_test.dart` | Alur kode reset kata sandi |
| `test/widget_test.dart` | Tombol simpan mati sebelum lengkap, sorotan keyakinan |

Keamanan server (hak kolom, policy, fungsi admin) ada di `supabase/setup.sql`
dan diuji manual sesuai daftar di README, karena butuh project Supabase
sungguhan.

Beberapa di antaranya bukan sekadar pengujian fungsional melainkan **penjaga
janji**: redaksi payload, cadangan yang gagal-tertutup, dan gerbang konfirmasi. Bila
salah satu gagal, yang rusak bukan fiturnya melainkan komitmen produknya.

---

## 12. Langkah Berikutnya

1. Uji parser dengan rekaman nyata di warung, lalu tala ulang ambang keyakinan.
2. Implementasi `NotificationListenerService` untuk QRIS sesuai rancangan di §10.
3. Login nomor HP setelah penyedia SMS dipilih.
4. Enkripsi isi cadangan di sisi klien bila dibutuhkan jaminan bahwa operator
   server pun tidak bisa membacanya.
