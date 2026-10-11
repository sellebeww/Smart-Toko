/// Daftar utang dan piutang: siapa yang belum bayar, dan ke siapa kita
/// masih berutang.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../../contacts/ui/contact_detail_screen.dart';
import '../data/debt_repository.dart';
import '../debts_providers.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(debtTotalsProvider).value ?? const DebtTotals();
    final balances = ref.watch(debtBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Utang & Piutang')),
      body: balances.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (items) {
          final receivables = [
            for (final b in items)
              if (b.direction == TxDirection.masuk) b,
          ];
          final payables = [
            for (final b in items)
              if (b.direction == TxDirection.keluar) b,
          ];
          if (items.isEmpty) return const _EmptyDebts();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _TotalsHeader(totals: totals),
              if (receivables.isNotEmpty) ...[
                const _SectionTitle('Belum dibayar pelanggan'),
                for (final b in receivables) _BalanceTile(balance: b),
              ],
              if (payables.isNotEmpty) ...[
                const _SectionTitle('Utang ke supplier'),
                for (final b in payables) _BalanceTile(balance: b),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TotalsHeader extends StatelessWidget {
  final DebtTotals totals;
  const _TotalsHeader({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, int amount, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              formatRupiah(amount),
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          cell('Harus ditagih', totals.receivable, theme.colorScheme.primary),
          const SizedBox(width: 12),
          cell('Harus dibayar', totals.payable, theme.colorScheme.error),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// "3 hari", "2 minggu" — sudah berapa lama sisa itu menggantung.
String ageLabel(DateTime since, DateTime now) {
  final days = startOfDay(now).difference(startOfDay(since)).inDays;
  if (days <= 0) return 'hari ini';
  if (days < 7) return '$days hari';
  if (days < 30) return '${days ~/ 7} minggu';
  return '${days ~/ 30} bulan';
}

class _BalanceTile extends StatelessWidget {
  final ContactBalance balance;
  const _BalanceTile({required this.balance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final old = DateTime.now().difference(balance.oldest).inDays >= 30;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContactDetailScreen(contactId: balance.contactId),
          ),
        ),
        title: Text(balance.name),
        subtitle: Text(
          '${balance.openCount} transaksi · sudah '
          '${ageLabel(balance.oldest, DateTime.now())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: old ? theme.colorScheme.error : null,
          ),
        ),
        trailing: Text(
          formatRupiah(balance.outstanding),
          style: theme.textTheme.titleSmall,
        ),
      ),
    );
  }
}

class _EmptyDebts extends StatelessWidget {
  const _EmptyDebts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.handshake_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak ada utang atau piutang',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Saat mencatat penjualan atau pembelian, nyalakan '
              '"Belum dibayar" dan pilih namanya. Atau ucapkan '
              '"Bu Sari ngutang nasi goreng dua lima belas ribu".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
