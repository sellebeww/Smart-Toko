/// Perkenalan singkat saat pertama kali dibuka.
///
/// Isinya bukan tur fitur, melainkan pernyataan posisi soal data. Kecurigaan
/// bahwa aplikasi pencatatan warung adalah alat pengawasan pajak itu nyata, dan
/// jawabannya harus muncul di layar pertama — bukan terkubur di kebijakan
/// privasi yang tak terbaca.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/settings_dao.dart';

class OnboardingScreen extends ConsumerWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('SmartToko', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Catat jualan tanpa pegang HP',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              const _Point(
                icon: Icons.mic,
                title: 'Tinggal ngomong',
                body:
                    'Sebut saja "jual indomie dua bungkus lima ribu". '
                    'Tangan lagi basah atau kotor pun tetap bisa mencatat.',
              ),
              const _Point(
                icon: Icons.check_circle_outline,
                title: 'Selalu kamu yang memutuskan',
                body:
                    'Hasil rekaman ditampilkan dulu untuk kamu periksa. '
                    'Tidak ada yang tersimpan tanpa kamu tekan Simpan.',
              ),
              const _Point(
                icon: Icons.phone_android,
                title: 'Datanya milik kamu',
                body:
                    'Catatan transaksi disimpan di HP ini saja. Tidak dikirim '
                    'ke mana pun, tidak dibagikan ke siapa pun, dan tidak '
                    'dilaporkan ke instansi mana pun. Yang ada di server hanya '
                    'akun dan profil toko (nama, kategori, alamat) supaya '
                    'tokomu bisa dibuka dari HP lain. Kalau mau mencadangkan '
                    'catatan ke cloud, kamu sendiri yang menyalakannya di '
                    'Pengaturan.',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () async {
                    await ref
                        .read(settingsDaoProvider)
                        .setFlag(SettingsKeys.onboardingDone, value: true);
                    onDone();
                  },
                  child: const Text('Mulai', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Point({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
