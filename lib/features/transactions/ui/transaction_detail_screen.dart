/// Detail satu transaksi, dengan koreksi dan hapus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../../contacts/contacts_providers.dart';
import '../../debts/debts_providers.dart';
import '../../debts/ui/payment_dialog.dart';
import '../../stores/stores_providers.dart';
import '../domain/receipt.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_record.dart';
import 'transaction_editor.dart';

final _transactionByIdProvider = FutureProvider.autoDispose
    .family<TxRecord?, String>((ref, id) {
      ref.watch(dataRevisionProvider);
      return ref.watch(transactionRepositoryProvider).findById(id);
    });

class TransactionDetailScreen extends ConsumerWidget {
  final String transactionId;

  const TransactionDetailScreen({super.key, required this.transactionId});

  Future<void> _correct(
    BuildContext context,
    WidgetRef ref,
    TxRecord record,
    String? contactName,
  ) async {
    final saved = await showTransactionEditor(
      context,
      ref,
      draft: TransactionDraft.fromRecord(record),
      replaceId: record.id,
      initialContactName: contactName,
    );
    // Koreksi menghasilkan id baru; detail lama sudah tidak ada.
    if (saved != null && context.mounted) Navigator.of(context).pop();
  }

  Future<void> _shareReceipt(
    WidgetRef ref,
    TxRecord record,
    String? contactName,
  ) => SharePlus.instance.share(
    ShareParams(
      text: buildReceiptText(
        record,
        storeName: ref.read(activeStoreProvider).value?.name ?? 'SmartToko',
        contactName: contactName,
      ),
      subject: 'Nota ${record.category.label}',
    ),
  );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TxRecord record,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: Text(
          '${record.category.label} ${formatRupiah(record.totalAmount)} '
          'pada ${formatShortDate(record.occurredAt)} '
          '${formatTime(record.occurredAt)} akan dihapus.'
          '${record.category == TxCategory.pembelian ? '\n\nStok dari pembelian ini ikut dibatalkan.' : ''}'
          '${record.onCredit ? '\n\nRiwayat pembayarannya ikut terhapus.' : ''}',
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
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(transactionRepositoryProvider).delete(record.id);
    ref.read(dataRevisionProvider.notifier).bump();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Transaksi dihapus')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_transactionByIdProvider(transactionId));
    final contactNames = ref.watch(contactNamesProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Detail transaksi')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (record) {
          if (record == null) {
            return const Center(child: Text('Transaksi sudah tidak ada.'));
          }
          final contactName = record.contactId == null
              ? null
              : contactNames[record.contactId];
          return _DetailBody(
            record: record,
            contactName: contactName,
            onShareReceipt: record.category == TxCategory.penjualan
                ? () => _shareReceipt(ref, record, contactName)
                : null,
            onCorrect: () => _correct(context, ref, record, contactName),
            onDelete: () => _delete(context, ref, record),
          );
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TxRecord record;
  final String? contactName;
  final VoidCallback onCorrect;
  final VoidCallback onDelete;

  /// Null untuk transaksi yang bukan penjualan (tidak ada yang dinotakan).
  final VoidCallback? onShareReceipt;

  const _DetailBody({
    required this.record,
    required this.contactName,
    required this.onShareReceipt,
    required this.onCorrect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIncome = record.direction == TxDirection.masuk;
    final color = isIncome
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(record.category.label, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${isIncome ? '+' : '−'}${formatRupiah(record.totalAmount)}',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.schedule,
                label: 'Waktu',
                value:
                    '${formatDayHeader(record.occurredAt)} ${record.occurredAt.year}, '
                    '${formatTime(record.occurredAt)}',
              ),
              _InfoRow(
                icon: switch (record.source) {
                  TxSource.voice => Icons.mic,
                  TxSource.qris => Icons.qr_code_2,
                  TxSource.manual => Icons.edit_outlined,
                },
                label: 'Sumber',
                value: record.source.label,
              ),
              if (contactName != null)
                _InfoRow(
                  icon: Icons.person_outline,
                  label: record.category == TxCategory.pembelian
                      ? 'Supplier'
                      : 'Pelanggan',
                  value: contactName!,
                ),
              _InfoRow(
                icon: Icons.badge_outlined,
                label: 'Dicatat oleh',
                value: record.recordedBy ?? '-',
              ),
              if (record.note case final note? when note.isNotEmpty)
                _InfoRow(icon: Icons.notes, label: 'Catatan', value: note),
            ],
          ),
        ),
        if (record.onCredit) ...[
          const SizedBox(height: 16),
          _PaymentsSection(record: record),
        ],
        const SizedBox(height: 16),
        Text('Barang', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              for (final item in record.items)
                ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    item.lineTotal == item.qty * item.unitPrice
                        ? '${formatQty(item.qty, item.unit)} × ${formatRupiah(item.unitPrice)}'
                        : '${formatQty(item.qty, item.unit)} · total '
                              '(≈ ${formatRupiah(item.unitPrice)}/${item.unit ?? 'satuan'})',
                  ),
                  trailing: Text(
                    formatRupiah(item.lineTotal),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (onShareReceipt != null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onShareReceipt,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Bagikan nota'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onCorrect,
                icon: const Icon(Icons.edit),
                label: const Text('Koreksi'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon, size: 20),
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );
}

/// Status kasbon, riwayat pembayaran, dan tombol mencatat pembayaran baru.
class _PaymentsSection extends ConsumerWidget {
  final TxRecord record;
  const _PaymentsSection({required this.record});

  Future<void> _deletePayment(
    BuildContext context,
    WidgetRef ref,
    String paymentId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pembayaran ini?'),
        content: const Text('Sisa yang harus dibayar akan bertambah lagi.'),
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
    await ref.read(debtRepositoryProvider).deletePayment(paymentId);
    ref.read(dataRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final payments =
        ref.watch(debtPaymentsProvider(record.id)).value ?? const [];
    final unpaid = record.isUnpaid;
    final isReceivable = record.direction == TxDirection.masuk;
    final progress = record.totalAmount == 0
        ? 1.0
        : (record.paidAmount / record.totalAmount).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  unpaid ? Icons.hourglass_bottom : Icons.check_circle_outline,
                  size: 20,
                  color: unpaid
                      ? const Color(0xFFAD642C)
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unpaid
                        ? (isReceivable
                              ? 'Belum dibayar pelanggan'
                              : 'Utang ke supplier')
                        : 'Lunas',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (unpaid)
                  Text(
                    'Sisa ${formatRupiah(record.outstanding)}',
                    style: theme.textTheme.titleSmall,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress, minHeight: 6),
            const SizedBox(height: 6),
            Text(
              'Dibayar ${formatRupiah(record.paidAmount)} dari '
              '${formatRupiah(record.totalAmount)}',
              style: theme.textTheme.bodySmall,
            ),
            for (final payment in payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(formatRupiah(payment.amount)),
                subtitle: Text(
                  [
                    formatShortDate(payment.paidAt),
                    if (payment.note != null) payment.note!,
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Hapus pembayaran',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _deletePayment(context, ref, payment.id),
                ),
              ),
            if (unpaid) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      showPaymentDialog(context, ref, record: record),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Catat pembayaran'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
