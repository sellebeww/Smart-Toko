/// Pengaturan privasi.
///
/// Semua sakelar di layar ini bawaannya MATI, dan masing-masing menyebutkan
/// secara spesifik apa yang terjadi bila dinyalakan. Sakelar "Bantuan AI"
/// sengaja dipisah dari "Sinkronisasi" walau keduanya sama-sama mengirim data
/// keluar: tujuan, penerima, dan isinya berbeda, jadi persetujuannya juga harus
/// terpisah.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/auth_providers.dart';
import '../../stores/domain/store_profile.dart';
import '../../stores/stores_providers.dart';
import '../../transactions/transactions_providers.dart';
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
            const _SectionHeader('Verifikasi Toko'),
            const _VerificationTile(),
            const Divider(),
            const _SectionHeader('Data kamu'),
            const _OwnershipNote(),
            SwitchListTile(
              value: state.syncEnabled,
              onChanged: !state.syncEnabled
                  ? null
                  : (value) => ref
                        .read(settingsControllerProvider.notifier)
                        .setSyncEnabled(value: value),
              title: const Text('Cadangkan ke cloud'),
              subtitle: const Text(
                'Belum tersedia di versi ini. Catatan transaksi tersimpan '
                'di HP ini dan belum dicadangkan ke server.',
              ),
            ),
            if (state.syncEnabled) const _SyncStatusTile(),
            const Divider(),
            const _SectionHeader('Bantuan AI untuk ucapan sulit'),
            SwitchListTile(
              value: state.llmEnabled,
              onChanged: state.hasApiKey
                  ? (value) => ref
                        .read(settingsControllerProvider.notifier)
                        .setLlmEnabled(value: value)
                  : null,
              title: const Text('Pakai AI saat ucapan sulit diurai'),
              subtitle: Text(
                state.hasApiKey
                    ? 'Kalau dinyalakan, KALIMAT YANG KAMU UCAPKAN dikirim ke '
                          'layanan AI pihak ketiga, hanya ketika pengurai biasa '
                          'gagal dan HP sedang online.'
                    : 'Isi kunci API dulu di bawah.',
              ),
            ),
            _ApiKeyTile(hasKey: state.hasApiKey),
            const Divider(),
            const _SectionHeader('Tangkap notifikasi QRIS'),
            const SwitchListTile(
              value: false,
              onChanged: null,
              title: Text('Catat otomatis dari notifikasi QRIS'),
              subtitle: Text(
                'Belum tersedia. Nanti fitur ini harus dinyalakan sendiri, '
                'hanya membaca notifikasi dari aplikasi pembayaran yang kamu '
                'pilih, dan hasilnya tetap harus kamu konfirmasi dulu.',
              ),
            ),
            const Divider(),
            const _SectionHeader('Demo'),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Admin: Kelola Verifikasi'),
              subtitle: const Text(
                'Simulasi peninjauan admin untuk demo — bukan sistem role sungguhan.',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminVerificationScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
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
              'Semua catatan transaksi tersimpan di HP ini saja dan tidak '
              'dikirim ke mana pun kecuali kamu menyalakannya sendiri di bawah. '
              'Akun, profil toko, dan foto verifikasi yang kamu kirim disimpan di server. Catatanmu bukan '
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

class _VerificationTile extends ConsumerWidget {
  const _VerificationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(activeStoreProvider);

    return storeAsync.when(
      loading: () => const ListTile(title: Text('Memuat...')),
      error: (error, _) => ListTile(title: Text('Gagal memuat toko: $error')),
      data: (store) => _VerificationBody(store: store),
    );
  }
}

class _VerificationBody extends StatelessWidget {
  final StoreProfile store;

  const _VerificationBody({required this.store});

  @override
  Widget build(BuildContext context) {
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
                child: Text(store.name, overflow: TextOverflow.ellipsis),
              ),
              VerificationStatusBadge(status: status),
            ],
          ),
          if (status == StoreVerificationStatus.rejected &&
              store.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'Alasan: ${store.rejectionReason}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                MaterialPageRoute(
                  builder: (_) =>
                      ConsentScreen(storeId: store.id, storeName: store.name),
                ),
              ),
              child: Text(
                status == StoreVerificationStatus.rejected
                    ? 'Ajukan Ulang'
                    : 'Mulai Verifikasi',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncStatusTile extends ConsumerWidget {
  const _SyncStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingSyncCountProvider);

    return ListTile(
      leading: const Icon(Icons.cloud_upload_outlined),
      title: Text('Menunggu terkirim: ${pending.value ?? 0}'),
      subtitle: const Text(
        'Dikirim saat aplikasi dibuka dan koneksi tersedia. '
        'Tidak ada pengiriman di latar belakang.',
      ),
      trailing: TextButton(
        onPressed: () async {
          await ref.read(syncQueueProvider).retryFailed();
          ref.invalidate(pendingSyncCountProvider);
        },
        child: const Text('Coba lagi'),
      ),
    );
  }
}

class _ApiKeyTile extends ConsumerStatefulWidget {
  final bool hasKey;

  const _ApiKeyTile({required this.hasKey});

  @override
  ConsumerState<_ApiKeyTile> createState() => _ApiKeyTileState();
}

class _ApiKeyTileState extends ConsumerState<_ApiKeyTile> {
  final _controller = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasKey && !_editing) {
      return ListTile(
        leading: const Icon(Icons.key),
        title: const Text('Kunci API tersimpan'),
        subtitle: const Text(
          'Disimpan di penyimpanan aman HP, bukan di kode aplikasi.',
        ),
        trailing: TextButton(
          onPressed: () =>
              ref.read(settingsControllerProvider.notifier).clearApiKey(),
          child: const Text('Hapus'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Kunci API',
              border: OutlineInputBorder(),
              helperText:
                  'Kunci milikmu sendiri. Tidak pernah ikut ke dalam APK.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                if (_controller.text.trim().isEmpty) return;
                await ref
                    .read(settingsControllerProvider.notifier)
                    .saveApiKey(_controller.text);
                _controller.clear();
                if (mounted) setState(() => _editing = false);
              },
              child: const Text('Simpan kunci'),
            ),
          ),
        ],
      ),
    );
  }
}
