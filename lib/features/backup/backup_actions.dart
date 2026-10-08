/// Aksi cadangan yang dipicu pengguna, dipakai Pengaturan dan layar utama.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../auth/auth_providers.dart';
import 'backup_providers.dart';
import 'backup_service.dart';

/// Mencadangkan toko aktif sekarang. Bila HP ini belum pernah mencadangkan
/// tetapi di server sudah ada cadangan (mis. dari HP lama), pengguna diminta
/// konfirmasi dulu supaya cadangan itu tidak tertimpa diam-diam.
///
/// Mengembalikan false hanya bila pengguna membatalkan.
Future<bool> backupNow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = ref.read(authStateChangesProvider).value?.uid;
  final storeId = ref.read(activeStoreIdProvider);
  if (uid == null || storeId == null) return true;
  final service = ref.read(backupServiceProvider);
  try {
    if (await service.lastBackupAt(storeId) == null) {
      final remote = await ref
          .read(backupStorageProvider)
          .lastModified(uid, storeId)
          .timeout(const Duration(seconds: 15));
      if (remote != null) {
        if (!context.mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ganti cadangan lama?'),
            content: Text(
              'Sudah ada cadangan toko ini dari ${formatShortDate(remote)}. '
              'Mencadangkan dari HP ini akan menggantinya. Bila ingin memakai '
              'isi cadangan itu, pilih "Pulihkan dari cadangan" dulu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ganti'),
              ),
            ],
          ),
        );
        if (ok != true) return false;
      }
    }
    await service
        .backupNow(ownerUid: uid, storeId: storeId)
        .timeout(const Duration(seconds: 60));
    ref.invalidate(backupStatusProvider);
    messenger.showSnackBar(
      const SnackBar(content: Text('Data toko sudah dicadangkan')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Belum bisa mencadangkan. Periksa koneksi lalu coba lagi.',
        ),
      ),
    );
  }
  return true;
}

/// Mengganti data toko aktif di HP ini dengan isi cadangan di server.
/// Konfirmasi ke pengguna menjadi tanggung jawab pemanggil.
Future<void> restoreBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = ref.read(authStateChangesProvider).value?.uid;
  final storeId = ref.read(activeStoreIdProvider);
  if (uid == null || storeId == null) return;
  try {
    final count = await ref
        .read(backupServiceProvider)
        .restore(ownerUid: uid, storeId: storeId)
        .timeout(const Duration(seconds: 60));
    ref.read(dataRevisionProvider.notifier).bump();
    ref.invalidate(backupStatusProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Berhasil memulihkan $count transaksi')),
    );
  } on BackupException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Gagal memulihkan. Periksa koneksi lalu coba lagi.'),
      ),
    );
  }
}
