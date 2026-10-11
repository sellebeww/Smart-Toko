/// Nota penjualan dalam bentuk teks, untuk dibagikan ke pelanggan.
///
/// Teks polos supaya bisa ditempel ke WhatsApp/SMS tanpa berkas dan tanpa
/// koneksi. Hanya memuat apa yang memang ada di transaksi; tidak ada data
/// pencatat atau akun.
library;

import '../../../core/format.dart';
import 'transaction_record.dart';

String buildReceiptText(
  TxRecord record, {
  required String storeName,
  String? contactName,
}) {
  final lines = <String>[
    storeName,
    '${formatShortDate(record.occurredAt)} ${formatTime(record.occurredAt)}',
    if (contactName != null) 'Untuk: $contactName',
    '',
  ];

  if (record.items.isEmpty) {
    lines.add(record.note ?? record.category.label);
  } else {
    for (final item in record.items) {
      lines.add('${item.name} ${formatQty(item.qty, item.unit)}');
      // Harga per satuan hanya ditampilkan bila memang bulat; kalau yang
      // disebut total, angka total baris sudah cukup.
      final exact = item.lineTotal == item.qty * item.unitPrice;
      lines.add(
        exact
            ? '  ${formatQty(item.qty, null)} x ${formatRupiah(item.unitPrice)} '
                  '= ${formatRupiah(item.lineTotal)}'
            : '  ${formatRupiah(item.lineTotal)}',
      );
    }
  }

  lines
    ..add('')
    ..add('TOTAL: ${formatRupiah(record.totalAmount)}');

  if (record.onCredit) {
    if (record.paidAmount > 0) {
      lines.add('Dibayar: ${formatRupiah(record.paidAmount)}');
    }
    lines.add(
      record.isUnpaid
          ? 'Sisa belum dibayar: ${formatRupiah(record.outstanding)}'
          : 'LUNAS',
    );
    if (record.isUnpaid && record.dueAt != null) {
      lines.add('Jatuh tempo: ${formatShortDate(record.dueAt!)}');
    }
  }

  lines
    ..add('')
    ..add('Terima kasih 🙏');
  return lines.join('\n');
}
