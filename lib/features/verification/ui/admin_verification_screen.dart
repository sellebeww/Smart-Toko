/// Panel admin untuk meninjau pengajuan verifikasi toko.
///
/// Hanya tampil untuk akun yang terdaftar di tabel `admins`. Menu yang
/// tersembunyi bukan pengamannya: setiap data dan keputusan di layar ini
/// lewat fungsi server yang menolak pemanggil bukan admin, dan setiap
/// keputusan tercatat di `verification_reviews`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/format.dart';
import '../admin_providers.dart';
import '../data/verification_repository.dart';
import '../domain/pending_verification.dart';
import '../domain/verification_status.dart';

final _documentUrlsProvider = FutureProvider.autoDispose
    .family<Map<VerificationDocument, String>, PendingVerification>(
      (ref, pending) => ref
          .watch(verificationRepositoryProvider)
          .signedUrls(pending.ownerUid, pending.storeId),
    );

class AdminVerificationScreen extends ConsumerWidget {
  const AdminVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingVerificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tinjau Verifikasi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pendingVerificationsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingVerificationsProvider.future),
        child: pending.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat pengajuan. Pastikan akun ini admin dan HP '
                  'terhubung ke internet, lalu tarik ke bawah untuk mencoba lagi.',
                ),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Tidak ada pengajuan yang menunggu.'),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _PendingCard(pending: items[index]),
            );
          },
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  final PendingVerification pending;

  const _PendingCard({required this.pending});

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _reviewing = false;
  PendingVerification get pending => widget.pending;

  Future<void> _reject() async {
    if (_reviewing) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alasan penolakan'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Contoh: Foto KTP buram, mohon foto ulang',
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    await _review(StoreVerificationStatus.rejected, reason);
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setujui verifikasi?'),
        content: Text(
          'Pastikan KTP, selfie, dan foto toko "${pending.name}" sudah '
          'sesuai sebelum menyetujui.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _review(StoreVerificationStatus.verified, null);
    }
  }

  Future<void> _review(StoreVerificationStatus status, String? reason) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(storeRepositoryProvider)
          .reviewVerification(
            pending.storeId,
            status: status,
            rejectionReason: reason,
          )
          .timeout(const Duration(seconds: 15));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == StoreVerificationStatus.verified
                ? '"${pending.name}" disetujui'
                : '"${pending.name}" ditolak',
          ),
        ),
      );
      ref.invalidate(pendingVerificationsProvider);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Keputusan belum tersimpan. Pengajuan mungkin sudah ditinjau '
              'admin lain, atau koneksi terputus.',
            ),
          ),
        );
        ref.invalidate(pendingVerificationsProvider);
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submitted = pending.submittedAt;
    final urls = ref.watch(_documentUrlsProvider(pending));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pending.name, style: theme.textTheme.titleMedium),
            Text('${pending.category.label} · ${pending.address}'),
            const SizedBox(height: 4),
            Text(
              [
                pending.ownerEmail ?? pending.ownerUid,
                if (submitted != null)
                  'diajukan ${formatShortDate(submitted)} ${formatTime(submitted)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            urls.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Gagal memuat dokumen.'),
              data: (urls) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final document in VerificationDocument.values)
                    _DocumentThumb(document: document, url: urls[document]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reviewing ? null : _reject,
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _reviewing ? null : _approve,
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

class _DocumentThumb extends StatelessWidget {
  final VerificationDocument document;
  final String? url;

  const _DocumentThumb({required this.document, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = url;

    return SizedBox(
      width: 96,
      child: Column(
        children: [
          InkWell(
            onTap: link == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _DocumentViewer(title: document.label, url: link),
                    ),
                  ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 96,
                height: 96,
                color: theme.colorScheme.surfaceContainerHighest,
                child: link == null
                    ? const Center(child: Text('Tidak ada'))
                    : Image.network(
                        link,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            document.label,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DocumentViewer extends StatelessWidget {
  final String title;
  final String url;

  const _DocumentViewer({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(title)),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }
}
