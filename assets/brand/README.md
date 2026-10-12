# Logo SmartToko

`smarttoko-logo.png` menggabungkan atap toko, struk dengan simbol Rp, dan
mikrofon untuk menjelaskan pencatatan keuangan toko lewat suara, dengan latar transparan.
Nama SmartToko ditampilkan terpisah oleh `BrandHeader` agar tetap terbaca pada
ukuran kecil. Aset dibuat dengan tool imagegen bawaan, bukan CLI.

## Ekspor aset platform

Jalankan dari root proyek pada macOS setelah mengganti PNG sumber:

```sh
swift -module-cache-path /tmp/smarttoko-swift-cache tool/export_brand.swift
```

Skrip mengekspor ikon launcher Android di lima density, ikon notifikasi
satu warna dari kanal alfa logo, splash Android (termasuk padding Android 12),
seluruh ukuran AppIcon iOS berdasarkan Contents.json, serta LaunchImage 1x–3x.
Logo sumber, ikon Android, dan gambar splash tetap transparan. AppIcon iOS
memakai latar krem `#F7F7F1` tanpa kanal alfa. Layar splash kedua platform
memakai warna krem yang sama dengan aplikasi.

Padding splash mengikuti [panduan Android](https://developer.android.com/develop/ui/views/launch/splash-screen).
Ikon launcher Android tetap memakai resource mipmap yang dirujuk manifest.

Untuk memperbarui gambar dokumentasi:

```sh
flutter test test/ui/figma_layout_test.dart --dart-define=WRITE_UI_PREVIEWS=true
cp build/ui-previews/{masuk,beranda,laporan,stok}.png docs/screenshots/
```

## Prompt revisi terbaru

```text
Use case: logo-brand
Asset type: transparent PNG logo symbol for SmartToko, an Indonesian app for recording shop income and expenses by voice.
Primary request: redesign the referenced logo so its primary message is shop bookkeeping / sales records, with voice entry as the secondary message. The current storefront with only a large microphone does not communicate bookkeeping clearly enough.
Input image: existing logo, reference for green palette and friendly rounded geometry only.
Subject: one cohesive compact mark: a shop awning forms the top of a transaction receipt, the receipt has a clear zigzag bottom edge, a prominent dark-green "Rp" currency label and two short bold ledger lines. Integrate one small recognizable microphone at the lower-right edge as a secondary accent, at about one third the receipt height. The receipt is the dominant shape, not the microphone.
Style: polished minimal flat vector-like branding; strong confident clean shapes, rounded corners, excellent optical balance, generous negative space, legible at 44–68 pixels.
Palette: forest green #176448 and green #25834D with a restrained lime #C1EE72 awning accent. Dark-green receipt outline, dark-green Rp and ledger lines. Receipt interior is transparent; no white fill.
Composition: single centered square symbol occupying about 88% of canvas, narrow balanced transparent margins.
Text (verbatim): "Rp" only, bold simple sans-serif lettering. No brand name or slogan inside image; app provides the wordmark separately.
Background: true transparent alpha throughout all empty space, including the receipt interior.
Avoid: enclosing tile or badge, backdrop, checkerboard pattern, shadows, gradients, 3D, texture, banknotes, coins, shopping cart, extra icons, fine details, mockups, watermark.
Deliver only the finished isolated logo.
```

## Prompt versi awal

```text
Use case: logo-brand
Asset type: production transparent PNG brand symbol for the existing SmartToko Flutter app, an Indonesian small-shop bookkeeping app with voice entry.
Primary request: design a beautiful new, minimal, professional logo symbol that stays legible at 44–68 pixels.
Subject: a friendly compact storefront silhouette with a simple awning and a cleverly integrated microphone in its open center, communicating a shop that records sales by voice. One unified balanced mark, bold clean geometry, softly rounded corners, very few parts.
Style/medium: crisp flat vector-like graphic, polished contemporary brand design.
Color palette: existing brand forest green #176448, green #25834D, restrained lime #C1EE72 accent. Strong dark-green outer silhouette for contrast on white and cream app surfaces.
Composition/framing: square canvas, single centered symbol filling roughly 88 percent of the canvas, equal narrow transparent margins.
Scene/backdrop: genuinely transparent alpha background, including all negative space inside the mark.
Text: none; the app renders the SmartToko wordmark separately.
Constraints: no enclosing background tile, no badge, no background square, no white backdrop, no checkerboard pattern, no gradients, no 3D, no shadows, no orbit, no leaves, no extra illustrations, no mockup, no watermark. Deliver only the finished isolated logo symbol.
```
