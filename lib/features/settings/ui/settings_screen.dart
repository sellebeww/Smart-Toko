/// Pengaturan akun, toko, dan privasi.
///
/// Semua sakelar pengiriman data bawaannya MATI, dan masing-masing
/// menyebutkan secara spesifik apa yang terjadi bila dinyalakan. "Bantuan AI"
/// sengaja dipisah dari "Cadangan cloud" walau keduanya sama-sama mengirim
/// data keluar: tujuan, penerima, dan isinya berbeda, jadi persetujuannya
/// juga harus terpisah.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/format.dart';
import '../../../core/supabase_config.dart';
import '../../account/account_deletion_service.dart';
import '../../app_lock/app_lock_controller.dart';
import '../../app_lock/ui/pin_dialogs.dart';
import '../../reminders/ui/reminder_settings_tiles.dart';
import '../../auth/auth_providers.dart';
import '../../backup/backup_actions.dart';
import '../../backup/backup_providers.dart';
import '../../stores/domain/store_profile.dart';
import '../../stores/stores_providers.dart';
import '../../stores/ui/add_store_screen.dart';
import '../../verification/admin_providers.dart';
import '../../verification/domain/verification_status.dart';
import '../../verification/ui/admin_verification_screen.dart';
import '../../verification/ui/consent_screen.dart';
import '../../verification/ui/verification_status_badge.dart';
import '../settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Gagal memuat: $error')),
        data: (state) => ListView(
          children: [
            const _SectionHeader('Akun'),
            const _AccountTile(),
            const Divider(),
            const _SectionHeader('Toko'),
            const _StoreTile(),
            const Divider(),
            const _SectionHeader('Data kamu'),
            const _OwnershipNote(),
            SwitchListTile(
              value: state.backupEnabled,
              onChanged: (value) => _setBackup(context, ref, value),
              title: const Text('Cadangkan otomatis ke cloud'),
              subtitle: const Text(
                'Kalau dinyalakan, salinan transaksi, barang, stok, dan kontak '
                'toko ini disimpan di akunmu, supaya bisa dipulihkan bila HP '
                'hilang atau ganti HP. Hanya kamu yang bisa membukanya.',
              ),
            ),
            _BackupTile(enabled: state.backupEnabled),
            const Divider(),
            if (SupabaseConfig.aiAssist) ...[
              const _SectionHeader('Bantuan AI untuk ucapan sulit'),
              SwitchListTile(
                value: state.llmEnabled,
                onChanged: (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .setLlmEnabled(value: value),
                title: const Text('Pakai AI saat ucapan sulit diurai'),
                subtitle: const Text(
                  'Kalau dinyalakan, KALIMAT YANG KAMU UCAPKAN dikirim ke server '
                  'SmartToko lalu ke layanan AI (Anthropic) untuk diurai, hanya '
                  'ketika pengurai di HP gagal dan HP sedang online. Hasilnya '
                  'tetap harus kamu periksa sebelum disimpan.',
                ),
              ),
            ],
            const Divider(),
            const _SectionHeader('Pengingat'),
            const ReminderSettingsTiles(),
            const Divider(),
            const _SectionHeader('Keamanan'),
            const _AppLockTiles(),
            const Divider(),
            const _SectionHeader('Laporan error'),
            SwitchListTile(
              value: state.errorReportsEnabled,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setErrorReportsEnabled(value: value),
              title: const Text('Kirim laporan error'),
              subtitle: const Text(
                'Kalau dinyalakan, saat aplikasi mengalami error, jenis error, '
                'versi aplikasi, dan jenis HP dikirim ke server SmartToko '
                'supaya bisa diperbaiki. Data transaksi, nama, dan kontakmu '
                'tidak ikut dikirim.',
              ),
            ),
            if (isAdmin) ...[
              const Divider(),
              const _SectionHeader('Admin'),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Tinjau pengajuan verifikasi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminVerificationScreen(),
                  ),
                ),
              ),
            ],
            if (SupabaseConfig.privacyUrl.isNotEmpty) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Kebijakan privasi'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openPrivacyPolicy(context),
              ),
            ],
            const Divider(),
            const _SectionHeader('Zona berbahaya'),
            const _DeleteAccountTile(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(SupabaseConfig.privacyUrl),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan tidak bisa dibuka.')),
      );
    }
  }

  /// Menyalakan cadangan langsung membuat cadangan pertama, supaya
  /// pengguna tahu saat itu juga apakah berhasil.
  Future<void> _setBackup(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setBackupEnabled(value: value);
    if (!value || !context.mounted) return;
    // Batal menimpa cadangan lama = cadangan otomatis juga tidak boleh
    // menimpanya nanti, jadi sakelarnya dikembalikan.
    if (!await backupNow(context, ref)) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setBackupEnabled(value: false);
    }
  }
}

/// Sakelar kunci PIN dan, bila menyala, pengubahan PIN.
class _AppLockTiles extends ConsumerWidget {
  const _AppLockTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(appLockControllerProvider).value?.enabled ?? false;
    return Column(
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: (value) => value
              ? showEnablePin(context, ref)
              : showDisablePin(context, ref),
          title: const Text('Kunci aplikasi dengan PIN'),
          subtitle: const Text(
            'Aplikasi meminta PIN saat dibuka dan setelah ditinggalkan lebih '
            'dari satu menit, supaya catatan keuangan tidak terbuka untuk '
            'orang yang meminjam HP-mu.',
          ),
        ),
        if (enabled)
          ListTile(
            title: const Text('Ubah PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showChangePin(context, ref),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _OwnershipNote extends StatelessWidget {
  const _OwnershipNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_android, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Catatan transaksi disimpan di HP ini dan tetap bisa dipakai '
              'tanpa internet. Catatan hanya dikirim ke server bila kamu '
              'menyalakan cadangan di bawah. Akun, profil toko, dan foto '
              'verifikasi yang kamu kirim disimpan di server. Catatanmu bukan '
              'milik kami dan tidak dibagikan ke pihak mana pun.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authStateChangesProvider).value?.email;

    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(email ?? ''),
      trailing: TextButton(
        onPressed: () async {
          try {
            await ref.read(authRepositoryProvider).signOut();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Gagal keluar. Silakan coba lagi.'),
                ),
              );
            }
          }
        },
        child: const Text('Keluar'),
      ),
    );
  }
}

class _StoreTile extends ConsumerWidget {
  const _StoreTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(activeStoreProvider);

    return storeAsync.when(
      loading: () => const ListTile(title: Text('Memuat...')),
      error: (error, _) =>
          const ListTile(title: Text('Data toko belum bisa dimuat.')),
      data: (store) => _StoreBody(store: store),
    );
  }
}

class _StoreBody extends StatelessWidget {
  final StoreProfile store;

  const _StoreBody({required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = store.verificationStatus;
    final canStart =
        status == StoreVerificationStatus.unverified ||
        status == StoreVerificationStatus.rejected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${store.category.label} · ${store.address}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ubah profil toko',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddStoreScreen(existing: store),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Verifikasi', style: theme.textTheme.bodyMedium),
              const Spacer(),
              VerificationStatusBadge(status: status),
            ],
          ),
          if (status == StoreVerificationStatus.rejected &&
              store.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'Alasan: ${store.rejectionReason}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (status == StoreVerificationStatus.pending) ...[
            const SizedBox(height: 8),
            const Text(
              'Pengajuan sedang ditinjau. Toko tetap bisa dipakai penuh sementara menunggu.',
            ),
          ],
          if (canStart) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ConsentScreen(storeId: store.id, storeName: store.name),
                ),
              ),
              child: Text(
                status == StoreVerificationStatus.rejected
                    ? 'Ajukan Ulang'
                    : 'Mulai Verifikasi (opsional)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupTile extends ConsumerStatefulWidget {
  final bool enabled;

  const _BackupTile({required this.enabled});

  @override
  ConsumerState<_BackupTile> createState() => _BackupTileState();
}

class _BackupTileState extends ConsumerState<_BackupTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulihkan dari cadangan?'),
        content: const Text(
          'Semua transaksi, barang, stok, dan kontak toko ini di HP ini akan '
          'DIGANTI dengan isi cadangan terakhir di cloud. Catatan yang belum '
          'sempat dicadangkan akan hilang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => restoreBackup(context, ref));
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(backupStatusProvider).value;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text(
            last == null
                ? 'Belum pernah dicadangkan dari HP ini'
                : 'Cadangan terakhir: ${formatShortDate(last)}, ${formatTime(last)}',
          ),
          subtitle: Text(
            widget.enabled
                ? 'Dicadangkan saat aplikasi dibuka atau ditutup bila ada '
                      'perubahan. Tidak ada pengiriman di latar belakang.'
                : 'Cadangan otomatis mati. Kamu tetap bisa mencadangkan manual.',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: () => _run(() => backupNow(context, ref)),
                  child: const Text('Cadangkan'),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('Pulihkan dari cadangan'),
          subtitle: const Text(
            'Ganti data toko di HP ini dengan isi cadangan.',
          ),
          enabled: !_busy,
          onTap: _restore,
        ),
      ],
    );
  }
}

class _DeleteAccountTile extends ConsumerStatefulWidget {
  const _DeleteAccountTile();

  @override
  ConsumerState<_DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends ConsumerState<_DeleteAccountTile> {
  bool _deleting = false;

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Hapus akun permanen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Akun, semua toko, foto verifikasi, cadangan cloud, dan semua '
                'catatan toko di HP ini akan dihapus. Ini tidak bisa '
                'dibatalkan. Export ke Excel dulu bila ingin menyimpan '
                'catatanmu.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Ketik HAPUS untuk melanjutkan',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: controller.text.trim() == 'HAPUS'
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Hapus akun'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true || !mounted) return;

    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(accountDeletionServiceProvider)
          .deleteAccount(uid)
          .timeout(const Duration(seconds: 60));
      // Gerbang login di app.dart mengganti layar begitu sesi berakhir.
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Akun belum terhapus. Periksa koneksi internet lalu coba lagi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: color),
      title: Text('Hapus akun', style: TextStyle(color: color)),
      subtitle: const Text('Menghapus akun dan seluruh datanya.'),
      enabled: !_deleting,
      trailing: _deleting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _delete,
    );
  }
}
