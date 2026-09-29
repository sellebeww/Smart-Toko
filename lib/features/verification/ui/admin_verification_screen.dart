/// Panel admin SIMULASI untuk menyetujui/menolak pengajuan verifikasi.
///
/// Ini bukan sistem admin sungguhan — tidak ada peran/role, siapa pun yang
/// login bisa membuka ini. Cukup untuk demo/tugas kuliah sesuai yang diminta:
/// alur upload + status yang bisa diubah manual untuk testing. Lihat
/// firestore.rules untuk batasan yang tetap berlaku (field lain milik toko
/// tidak bisa diubah lewat celah ini).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../stores/domain/store_profile.dart';
import '../domain/verification_status.dart';

/// autoDispose: query lintas-akun ini hanya perlu hidup selama panel admin
/// terbuka.
final _pendingStoresProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(storeRepositoryProvider).watchPendingStores();
});

class AdminVerificationScreen extends ConsumerWidget {
  const AdminVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(_pendingStoresProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin: Verifikasi Toko (Demo)')),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Gagal memuat: $error')),
        data: (stores) {
          if (stores.isEmpty) {
            return const Center(
              child: Text('Tidak ada pengajuan yang menunggu.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stores.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _PendingCard(store: stores[index]),
          );
        },
      ),
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  final StoreProfile store;

  const _PendingCard({required this.store});

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _reviewing = false;
  StoreProfile get store => widget.store;

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    if (_reviewing) return;
    var reasonText = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alasan penolakan'),
        content: TextField(
          onChanged: (value) => reasonText = value,
          decoration: const InputDecoration(hintText: 'Contoh: Foto KTP buram'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reasonText.trim()),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await _review(
      context,
      ref,
      status: StoreVerificationStatus.rejected,
      rejectionReason: reason,
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref, {
    required StoreVerificationStatus status,
    String? rejectionReason,
  }) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(storeRepositoryProvider)
          .setVerificationStatus(
            store.id,
            status: status,
            rejectionReason: rejectionReason,
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Belum bisa menyimpan keputusan. Periksa koneksi dan status pengajuan.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.name, style: Theme.of(context).textTheme.titleMedium),
            Text('${store.category.label} · ${store.address}'),
            Text(
              'Pemilik uid: ${store.ownerUid}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reviewing ? null : () => _reject(context, ref),
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _reviewing
                        ? null
                        : () => _review(
                            context,
                            ref,
                            status: StoreVerificationStatus.verified,
                          ),
                    child: const Text('Setujui'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
