/// Detail pelanggan/supplier: info kontak dan riwayat transaksinya.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/contact_dao.dart';
import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../../debts/data/debt_repository.dart';
import '../../debts/debts_providers.dart';
import '../../debts/reminder.dart';
import '../../stores/stores_providers.dart';
import '../../transactions/domain/transaction_record.dart';
import '../../transactions/ui/transaction_detail_screen.dart';
import '../../transactions/ui/transaction_tile.dart';
import 'contact_form_sheet.dart';

final _contactDetailProvider = FutureProvider.autoDispose
    .family<
      ({
        ContactRecord contact,
        List<TxRecord> transactions,
        PaymentRecord record,
      })?,
      String
    >((ref, id) async {
      ref.watch(dataRevisionProvider);
      final contact = await ref.watch(contactDaoProvider).findById(id);
      if (contact == null) return null;
      final record = await ref
          .watch(debtRepositoryProvider)
          .paymentRecord(contact.storeId, id);
      final transactions = await ref
          .watch(transactionRepositoryProvider)
          .listBetween(
            storeId: contact.storeId,
            from: DateTime.fromMillisecondsSinceEpoch(0),
            to: DateTime.now().add(const Duration(days: 1)),
            contactId: id,
          );
      return (contact: contact, transactions: transactions, record: record);
    });

class ContactDetailScreen extends ConsumerWidget {
  final String contactId;

  const ContactDetailScreen({super.key, required this.contactId});

  /// Mengirim pengingat lewat WhatsApp bila nomornya valid; selain itu lewat
  /// menu bagikan, supaya pengguna tetap bisa memilih aplikasi sendiri.
  Future<void> _remind(
    BuildContext context,
    WidgetRef ref,
    ContactRecord contact,
    List<TxRecord> unpaid,
  ) async {
    final message = buildReminderMessage(
      contactName: contact.name,
      storeName: ref.read(activeStoreProvider).value?.name ?? 'toko kami',
      outstanding: unpaid.fold(0, (sum, t) => sum + t.outstanding),
      openCount: unpaid.length,
      since: unpaid
          .map((t) => t.occurredAt)
          .reduce((a, b) => a.isBefore(b) ? a : b),
      dueAt: _earliestDue(unpaid),
    );
    final link = whatsappLink(contact.phone, message);
    var opened = false;
    if (link != null) {
      try {
        opened = await launchUrl(link, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) await SharePlus.instance.share(ShareParams(text: message));
  }

  static DateTime? _earliestDue(List<TxRecord> unpaid) {
    DateTime? earliest;
    for (final t in unpaid) {
      final due = t.dueAt;
      if (due != null && (earliest == null || due.isBefore(earliest))) {
        earliest = due;
      }
    }
    return earliest;
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ContactRecord contact,
    int outstanding,
  ) async {
    if (outstanding > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${contact.name} belum lunas'),
          content: Text(
            'Masih ada sisa ${formatRupiah(outstanding)}. Lunasi dulu '
            'sebelum menghapus nama ini, supaya catatan utangnya tidak hilang.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus ${contact.name}?'),
        content: const Text(
          'Transaksinya tetap tersimpan, hanya tidak lagi terhubung ke nama ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(contactDaoProvider).delete(contact.id);
    ref.read(dataRevisionProvider.notifier).bump();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_contactDetailProvider(contactId));
    final theme = Theme.of(context);
    final data = async.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(data?.contact.name ?? ''),
        actions: [
          if (data != null) ...[
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showContactForm(
                context,
                kind: data.contact.kind,
                existing: data.contact,
              ),
            ),
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(
                context,
                ref,
                data.contact,
                data.transactions.fold(0, (sum, t) => sum + t.outstanding),
              ),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Kontak sudah dihapus.'));
          }
          final c = data.contact;
          final txs = data.transactions;
          final total = txs.fold<int>(0, (sum, t) => sum + t.totalAmount);
          final unpaid = [
            for (final t in txs)
              if (t.isUnpaid) t,
          ];
          final owed = unpaid.fold<int>(0, (sum, t) => sum + t.outstanding);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (owed > 0)
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  color: const Color(0xFFFFF1DF),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unpaid.first.direction == TxDirection.masuk
                              ? 'Belum dibayar ${c.name}'
                              : 'Utang ke ${c.name}',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupiah(owed),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${unpaid.length} transaksi belum lunas. Buka '
                          'transaksinya untuk mencatat pembayaran.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (unpaid.any((t) => t.isOverdue(DateTime.now())))
                          Text(
                            'Ada yang sudah lewat jatuh tempo.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (c.kind == ContactKind.pelanggan) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => _remind(context, ref, c, unpaid),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Kirim pengingat'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(c.kind.label),
                    ),
                    if (c.location != null)
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(c.location!),
                      ),
                    if (c.phone != null)
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(c.phone!),
                      ),
                    if (c.note != null)
                      ListTile(
                        leading: const Icon(Icons.notes),
                        title: Text(c.note!),
                      ),
                  ],
                ),
              ),
              if (data.record.settled > 0)
                _PaymentRecordTile(record: data.record),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Riwayat transaksi (${txs.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (total > 0)
                      Text(
                        formatRupiah(total),
                        style: theme.textTheme.titleSmall,
                      ),
                  ],
                ),
              ),
              if (txs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Belum ada transaksi. Pilih ${c.name} di layar konfirmasi '
                    'saat mencatat ${c.kind == ContactKind.pelanggan ? 'penjualan' : 'pembelian'}.',
                  ),
                )
              else
                for (final t in txs)
                  TransactionTile(
                    record: t,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            TransactionDetailScreen(transactionId: t.id),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// "Lunas 6 kali · 2 kali telat · rata-rata 9 hari": bahan pertimbangan
/// sebelum memberi kasbon lagi.
class _PaymentRecordTile extends StatelessWidget {
  final PaymentRecord record;
  const _PaymentRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = record.averageDaysToSettle;
    final parts = [
      'Lunas ${record.settled} kali',
      if (record.late > 0)
        '${record.late} kali telat'
      else if (record.withDueDate > 0)
        'selalu tepat waktu',
      if (avg != null) 'rata-rata ${avg.round()} hari',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          record.late > 0 ? Icons.history_toggle_off : Icons.verified_outlined,
          color: record.late > 0
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
        title: const Text('Riwayat bayar kasbon'),
        subtitle: Text(parts.join(' · ')),
      ),
    );
  }
}
