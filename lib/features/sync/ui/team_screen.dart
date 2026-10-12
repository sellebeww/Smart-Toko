/// Sinkronisasi antar-HP dan karyawan (pemilik), atau keluar dari toko
/// (karyawan).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/format.dart';
import '../../stores/domain/store_profile.dart';
import '../../stores/stores_providers.dart';
import '../sync_providers.dart';
import '../team_repository.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(activeStoreProvider).value;
    final staff = ref.watch(isStaffProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(staff ? 'Toko tempat kerja' : 'Sinkronisasi & karyawan'),
      ),
      body: store == null
          ? const Center(child: CircularProgressIndicator())
          : staff
          ? _StaffView(store: store)
          : _OwnerView(store: store),
    );
  }
}

class _SyncStatusLine extends ConsumerWidget {
  const _SyncStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null || !status.enabledHere) return const SizedBox.shrink();
    final last = status.lastSyncedAt;
    final text =
        status.error ??
        [
          last == null
              ? 'Belum pernah tersinkron'
              : 'Tersinkron ${formatShortDate(last)} ${formatTime(last)}',
          if (status.pending > 0) '${status.pending} perubahan menunggu',
        ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(
            status.error != null
                ? Icons.cloud_off_outlined
                : status.pending > 0
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _OwnerView extends ConsumerStatefulWidget {
  final StoreProfile store;
  const _OwnerView({required this.store});

  @override
  ConsumerState<_OwnerView> createState() => _OwnerViewState();
}

class _OwnerViewState extends ConsumerState<_OwnerView> {
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _enable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nyalakan sinkronisasi?'),
        content: const Text(
          'Seluruh catatan toko ini (transaksi, barang, stok, kontak, '
          'kasbon) disimpan juga di server SmartToko, supaya bisa dipakai '
          'bersama di HP lain milikmu dan oleh karyawan yang kamu undang.\n\n'
          'Hanya kamu dan karyawanmu yang bisa membukanya. Karyawan tidak '
          'bisa melihat modal, laba, dan laporan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Nyalakan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final engine = ref.read(syncEngineProvider);
    try {
      // Antrean disiapkan dulu, baru server dinyalakan (lihat
      // prepareFirstDevice).
      await engine.prepareFirstDevice(widget.store.id);
      await ref
          .read(teamRepositoryProvider)
          .setStoreSync(widget.store.id, enabled: true);
      await engine.sync(widget.store.id);
      ref.invalidate(syncStatusProvider);
      _snack('Sinkronisasi menyala.');
    } catch (_) {
      await engine.disableLocal(widget.store.id);
      _snack('Belum bisa menyalakan sinkronisasi. Periksa internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Matikan sinkronisasi?'),
        content: const Text(
          'Data toko ini di server dihapus, semua karyawan dikeluarkan, dan '
          'undangan dibatalkan. Catatan di HP ini tetap ada.',
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
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Matikan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      // Kirim perubahan terakhir dulu: HP lain milikmu mungkin masih butuh.
      try {
        await ref.read(syncEngineProvider).sync(widget.store.id);
      } catch (_) {
        // Tetap lanjut mematikan; catatan di HP ini tidak hilang.
      }
      await ref
          .read(teamRepositoryProvider)
          .setStoreSync(widget.store.id, enabled: false);
      await ref.read(syncEngineProvider).disableLocal(widget.store.id);
      ref.invalidate(syncStatusProvider);
      _snack('Sinkronisasi dimatikan.');
    } catch (_) {
      _snack('Belum bisa mematikan. Periksa internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(teamRepositoryProvider)
          .createInvite(widget.store.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            _InviteDialog(code: formatInviteCode(code), store: widget.store),
      );
    } on TeamException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Belum bisa membuat undangan. Periksa internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TeamMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Keluarkan ${member.email}?'),
        content: const Text(
          'Ia tidak bisa lagi membuka toko ini, dan salinan toko di HP-nya '
          'dihapus saat aplikasinya tersambung. Catatan yang sudah ia buat '
          'tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(teamRepositoryProvider)
          .removeMember(widget.store.id, member.userId);
      ref.invalidate(teamMembersProvider(widget.store.id));
    } catch (_) {
      _snack('Belum bisa mengeluarkan. Periksa internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.store.syncEnabled;
    final members = enabled
        ? ref.watch(teamMembersProvider(widget.store.id))
        : null;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: _busy ? null : (on) => on ? _enable() : _disable(),
          title: const Text('Sinkronkan antar-HP'),
          subtitle: const Text(
            'Pakai toko ini di beberapa HP sekaligus, dan izinkan karyawan '
            'mencatat dari HP mereka.',
          ),
        ),
        if (enabled) const _SyncStatusLine(),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Karyawan', style: theme.textTheme.titleSmall),
        ),
        if (!enabled)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Nyalakan sinkronisasi dulu untuk mengundang karyawan.',
            ),
          )
        else ...[
          members!.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => const ListTile(
              title: Text('Daftar karyawan belum bisa dimuat.'),
            ),
            data: (list) => list.isEmpty
                ? const ListTile(title: Text('Belum ada karyawan.'))
                : Column(
                    children: [
                      for (final m in list)
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: Text(m.email),
                          subtitle: Text(
                            'Bergabung ${formatShortDate(m.joinedAt)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Keluarkan',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _remove(m),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Undang karyawan'),
            ),
          ),
        ],
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            'Karyawan bisa: mencatat transaksi, melihat riwayat dan stok, '
            'mencatat pembayaran kasbon, menambah kontak.\n'
            'Karyawan tidak bisa: melihat laporan, laba, dan modal; mengubah '
            'atau menghapus catatan orang lain; mengatur toko dan karyawan.',
          ),
        ),
      ],
    );
  }
}

class _InviteDialog extends StatelessWidget {
  final String code;
  final StoreProfile store;
  const _InviteDialog({required this.code, required this.store});

  String get _message =>
      'Kamu diundang mencatat transaksi untuk ${store.name} di SmartToko.\n'
      'Buka SmartToko, pilih "Gabung toko", lalu masukkan kode: $code\n'
      '(berlaku 48 jam, sekali pakai)';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kode undangan'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          code,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Berlaku 48 jam dan hanya untuk satu orang. Berikan hanya ke '
          'karyawanmu.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Kode disalin')));
          }
        },
        child: const Text('Salin'),
      ),
      FilledButton.icon(
        onPressed: () => SharePlus.instance.share(ShareParams(text: _message)),
        icon: const Icon(Icons.share),
        label: const Text('Bagikan'),
      ),
    ],
  );
}

class _StaffView extends ConsumerWidget {
  final StoreProfile store;
  const _StaffView({required this.store});

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Keluar dari ${store.name}?'),
        content: const Text(
          'Salinan toko ini dihapus dari HP-mu. Catatan yang sudah kamu '
          'buat tetap ada di toko. Untuk kembali, minta kode undangan baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Kirim catatan terakhir sebelum keluar.
      await ref.read(syncEngineProvider).sync(store.id);
      await ref.read(teamRepositoryProvider).leaveStore(store.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum bisa keluar. Periksa internet dulu.'),
          ),
        );
      }
      return;
    }
    await ref.read(syncEngineProvider).removeLocalStore(store.id);
    await ref.read(activeStoreIdProvider.notifier).set(null);
    ref.invalidate(userStoresProvider);
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(store.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Kamu tercatat sebagai karyawan di toko ini.'),
      const SizedBox(height: 8),
      const _SyncStatusLine(),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => _leave(context, ref),
        icon: const Icon(Icons.logout),
        label: const Text('Keluar dari toko ini'),
      ),
    ],
  );
}
