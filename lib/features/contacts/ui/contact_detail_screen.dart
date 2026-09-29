/// Detail pelanggan/supplier: info kontak dan riwayat transaksinya.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/contact_dao.dart';
import '../../../core/format.dart';
import '../../transactions/domain/transaction_record.dart';
import '../../transactions/ui/transaction_detail_screen.dart';
import '../../transactions/ui/transaction_tile.dart';
import 'contact_form_sheet.dart';

final _contactDetailProvider = FutureProvider.autoDispose
    .family<({ContactRecord contact, List<TxRecord> transactions})?, String>((
      ref,
      id,
    ) async {
      ref.watch(dataRevisionProvider);
      final contact = await ref.watch(contactDaoProvider).findById(id);
      if (contact == null) return null;
      final transactions = await ref
          .watch(transactionRepositoryProvider)
          .listBetween(
            storeId: contact.storeId,
            from: DateTime.fromMillisecondsSinceEpoch(0),
            to: DateTime.now().add(const Duration(days: 1)),
            contactId: id,
          );
      return (contact: contact, transactions: transactions);
    });

class ContactDetailScreen extends ConsumerWidget {
  final String contactId;

  const ContactDetailScreen({super.key, required this.contactId});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ContactRecord contact,
  ) async {
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
              onPressed: () => _delete(context, ref, data.contact),
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
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
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
