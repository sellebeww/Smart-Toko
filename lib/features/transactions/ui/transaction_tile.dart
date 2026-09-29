/// Satu baris transaksi, dipakai di layar utama, riwayat, dan detail kontak.
///
/// Ikon menunjukkan dari mana catatan berasal (suara/QRIS/ketik) — supaya
/// hasil pencatatan suara yang belum sempat diperiksa ulang mudah dikenali —
/// sedangkan warna dan tanda +/- menunjukkan arahnya.
library;

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../domain/transaction_record.dart';

class TransactionTile extends StatelessWidget {
  final TxRecord record;
  final String? contactName;

  /// Masih antre dikirim ke server (hanya bila sinkronisasi dinyalakan).
  final bool pendingSync;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.record,
    this.contactName,
    this.pendingSync = false,
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isIncome
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.errorContainer,
          child: Tooltip(
            message: record.source.label,
            child: Icon(
              sourceIcon(record.source),
              size: 20,
              color: isIncome
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                [
                  formatTime(record.occurredAt),
                  record.category.label,
                  ?contactName,
                  ?recorderLabel(record.recordedBy),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pendingSync) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Belum terkirim ke server',
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        trailing: Text(
          '${isIncome ? '+' : '−'}${formatRupiah(record.totalAmount)}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
