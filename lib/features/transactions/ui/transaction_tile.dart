/// Satu baris transaksi, dipakai di layar utama, riwayat, dan detail kontak.
///
/// Ikon menunjukkan dari mana catatan berasal (suara/QRIS/ketik) — supaya
/// hasil pencatatan suara yang belum sempat diperiksa ulang mudah dikenali —
/// sedangkan warna dan tanda +/- menunjukkan arahnya.
library;

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/ui/figma_icon.dart';
import '../../../core/transaction_kind.dart';
import '../../debts/due_label.dart';
import '../domain/transaction_record.dart';

class TransactionTile extends StatelessWidget {
  final TxRecord record;
  final String? contactName;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.record,
    this.contactName,
    this.onTap,
  });

  /// "budi" dari "budi@contoh.com" — cukup untuk membedakan pencatat tanpa
  /// memamerkan alamat lengkapnya di daftar.
  static String? recorderLabel(String? email) {
    if (email == null || email.isEmpty) return null;
    final at = email.indexOf('@');
    return at <= 0 ? email : email.substring(0, at);
  }

  static IconData sourceIcon(TxSource source) => switch (source) {
    TxSource.voice => Icons.mic,
    TxSource.qris => Icons.qr_code_2,
    TxSource.manual => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = record.direction == TxDirection.masuk;
    final color = isIncome
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    final title = record.items.isEmpty
        ? record.category.label
        : record.items
              .map((i) => '${i.name} ×${formatQty(i.qty, i.unit)}')
              .join(', ');

    final subtitle = [
      record.category.label,
      formatTime(record.occurredAt),
      record.source.label,
      ?contactName,
      ?recorderLabel(record.recordedBy),
    ].join(' · ');
    final amount = '${isIncome ? '+' : '−'}${formatRupiah(record.totalAmount)}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              final value = Text(
                amount,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isIncome
                          ? const Color(0xFFE8F2E9)
                          : const Color(0xFFFFF1DF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: FigmaIcon(
                      isIncome
                          ? 'c7d8d'
                          : record.category == TxCategory.pembelian
                          ? '1c65f'
                          : 'ad58d',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (record.onCredit) ...[
                          const SizedBox(height: 4),
                          _CreditBadge(record: record),
                        ],
                        if (compact) ...[const SizedBox(height: 8), value],
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: value,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "Belum lunas · sisa Rp 40.000" atau "Lunas" untuk transaksi kasbon.
class _CreditBadge extends StatelessWidget {
  final TxRecord record;
  const _CreditBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    final unpaid = record.isUnpaid;
    final now = DateTime.now();
    final overdue = record.isOverdue(now);
    final due = record.dueAt;
    final label = unpaid
        ? [
            'Belum lunas · sisa ${formatRupiah(record.outstanding)}',
            if (due != null) dueLabel(due, now),
          ].join(' · ')
        : 'Lunas';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: overdue
            ? const Color(0xFFFDE7E7)
            : unpaid
            ? const Color(0xFFFFF1DF)
            : const Color(0xFFE8F2E9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: overdue
              ? const Color(0xFFB3261E)
              : unpaid
              ? const Color(0xFFAD642C)
              : const Color(0xFF176448),
        ),
      ),
    );
  }
}
