/// Consent eksplisit sebelum minta foto KTP/selfie.
///
/// Ditampilkan SEBELUM layar upload, bukan sesudahnya — supaya user tahu
/// persis data apa yang diminta dan untuk apa sebelum kamera terbuka.
library;

import 'package:flutter/material.dart';

import 'upload_screen.dart';

/// Naikkan setiap kali isi teks persetujuan di bawah berubah, supaya catatan
/// persetujuan di data toko tetap menunjuk ke teks yang benar-benar dibaca.
const String identityConsentVersion = 'ktp-v3';

class ConsentScreen extends StatefulWidget {
  final String storeId;
  final String storeName;

  const ConsentScreen({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Toko')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sebelum lanjut', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text(
                'Untuk verifikasi "${widget.storeName}", kamu akan diminta memotret:\n\n'
                '• KTP pemilik\n'
                '• Foto toko/warung dari luar\n'
                '• Selfie sambil memegang KTP\n'
                '• NIB/izin usaha (opsional, kalau punya)',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bagaimana datanya dipakai',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Foto-foto ini HANYA dipakai untuk memverifikasi kepemilikan '
                      'toko. Disimpan terenkripsi di server, dan aturan '
                      'akses aplikasi hanya mengizinkan akunmu sendiri membukanya. '
                      'Tidak ditampilkan di layar mana pun di aplikasi ini setelah '
                      'diunggah, dan tidak ikut dalam data yang diekspor. Salinan '
                      'sementara yang dibuat aplikasi dihapus setelah selesai atau '
                      'dibatalkan; foto asli di galeri tetap ada.\n\n'
                      'Verifikasi sepenuhnya opsional — toko tetap bisa dipakai '
                      'penuh tanpa ini.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _agreed,
                onChanged: (value) => setState(() => _agreed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Saya mengerti dan setuju datanya dipakai seperti di atas',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _agreed
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UploadScreen(
                            storeId: widget.storeId,
                            storeName: widget.storeName,
                            consentVersion: identityConsentVersion,
                          ),
                        ),
                      )
                    : null,
                child: const Text('Lanjut'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
