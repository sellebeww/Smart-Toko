/// Menyusun laporan transaksi dalam format Excel (.xlsx).
///
/// Hanya data transaksi yang ditulis. Data verifikasi toko (KTP, foto, NIB)
/// tidak pernah dibaca modul ini — berkasnya hanya menerima [TxRecord].
library;

import 'package:excel/excel.dart';

import '../../core/format.dart';
import '../../core/transaction_kind.dart';
import '../transactions/domain/transaction_record.dart';

const String transactionsSheetName = 'Transaksi';
const String dailySummarySheetName = 'Ringkasan Harian';

const List<String> transactionsHeader = [
  'Tanggal',
  'Jam',
  'Nama Item',
  'Jumlah',
  'Harga Satuan',
  'Total',
  'Sumber',
  'Dicatat Oleh',
  'Satuan',
  'Kategori',
  'Pelanggan/Supplier',
  'Status Bayar',
  'Sisa Belum Dibayar',
  'Jatuh Tempo',
];

const List<String> dailySummaryHeader = [
  'Tanggal',
  'Total Transaksi',
  'Pendapatan',
  'Pengeluaran',
  'Keuntungan',
];

final CellStyle _header = CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#E8F5E9'),
);
final CellStyle _money = CellStyle(
  numberFormat: const CustomNumericNumFormat(formatCode: '#,##0'),
);
final CellStyle _moneyBold = CellStyle(
  bold: true,
  numberFormat: const CustomNumericNumFormat(formatCode: '#,##0'),
);
final CellStyle _bold = CellStyle(bold: true);

/// "SmartToko_Warteg_Bu_Ani_2026-09-01_2026-09-29.xlsx". [to] inklusif.
String exportFileName({
  required String storeName,
  required DateTime from,
  required DateTime to,
}) {
  final safe = storeName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'SmartToko_${safe.isEmpty ? 'Toko' : safe}_'
      '${formatIsoDate(from)}_${formatIsoDate(to)}.xlsx';
}

/// [records] boleh dalam urutan apa pun; berkas selalu ditulis dari yang
/// terlama ke terbaru. Pengeluaran ditulis sebagai angka positif di kolom
/// Total — arahnya terbaca dari kolom Kategori, dan ringkasan harian
/// memisahkan pendapatan dan pengeluaran.
List<int> buildTransactionsWorkbook(
  List<TxRecord> records, {
  Map<String, String> contactNames = const {},
}) {
  final sorted = [...records]
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final tx = excel[transactionsSheetName];
  final summary = excel[dailySummarySheetName];
  excel.setDefaultSheet(transactionsSheetName);
  if (defaultSheet != null && defaultSheet != transactionsSheetName) {
    excel.delete(defaultSheet);
  }

  _writeRow(tx, 0, [
    for (final h in transactionsHeader) (TextCellValue(h), _header),
  ]);
  var row = 1;
  for (final record in sorted) {
    final items = record.items.isEmpty
        ? [
            TxItemRecord(
              id: '',
              transactionId: record.id,
              name: record.note ?? record.category.label,
              qty: 1,
              unitPrice: record.totalAmount,
              lineTotal: record.totalAmount,
            ),
          ]
        : record.items;
    final status = !record.onCredit
        ? 'Tunai'
        : record.isUnpaid
        ? 'Belum lunas'
        : 'Lunas';
    var firstRow = true;
    for (final item in items) {
      // Sisa ditulis di baris pertama transaksi saja, supaya menjumlahkan
      // kolom ini tidak menghitung satu kasbon berkali-kali.
      final remaining = firstRow && record.isUnpaid ? record.outstanding : null;
      firstRow = false;
      _writeRow(tx, row++, [
        (TextCellValue(formatIsoDate(record.occurredAt)), null),
        (TextCellValue(formatTime(record.occurredAt)), null),
        (TextCellValue(item.name), null),
        (IntCellValue(item.qty), null),
        (IntCellValue(item.unitPrice), _money),
        (IntCellValue(item.lineTotal), _money),
        (TextCellValue(record.source.label), null),
        (TextCellValue(record.recordedBy ?? '-'), null),
        (TextCellValue(item.unit ?? ''), null),
        (TextCellValue(record.category.label), null),
        (
          TextCellValue(
            record.contactId == null
                ? ''
                : contactNames[record.contactId] ?? '',
          ),
          null,
        ),
        (TextCellValue(status), null),
        remaining == null
            ? (TextCellValue(''), null)
            : (IntCellValue(remaining), _money),
        (
          TextCellValue(
            record.isUnpaid && record.dueAt != null
                ? formatIsoDate(record.dueAt!)
                : '',
          ),
          null,
        ),
      ]);
    }
  }

  _writeRow(summary, 0, [
    for (final h in dailySummaryHeader) (TextCellValue(h), _header),
  ]);
  final days = summarizeByDay(sorted);
  var sumCount = 0, sumIn = 0, sumOut = 0;
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    sumCount += d.count;
    sumIn += d.pendapatan;
    sumOut += d.pengeluaran;
    _writeRow(summary, i + 1, [
      (TextCellValue(formatIsoDate(d.day)), null),
      (IntCellValue(d.count), null),
      (IntCellValue(d.pendapatan), _money),
      (IntCellValue(d.pengeluaran), _money),
      (IntCellValue(d.keuntungan), _money),
    ]);
  }
  _writeRow(summary, days.length + 1, [
    (TextCellValue('TOTAL'), _bold),
    (IntCellValue(sumCount), _bold),
    (IntCellValue(sumIn), _moneyBold),
    (IntCellValue(sumOut), _moneyBold),
    (IntCellValue(sumIn - sumOut), _moneyBold),
  ]);

  for (var c = 0; c < transactionsHeader.length; c++) {
    tx.setColumnAutoFit(c);
  }
  for (var c = 0; c < dailySummaryHeader.length; c++) {
    summary.setColumnAutoFit(c);
  }

  return excel.encode()!;
}

typedef DaySummary = ({
  DateTime day,
  int count,
  int pendapatan,
  int pengeluaran,
  int keuntungan,
});

/// Ringkasan per hari, terlama dulu. Keuntungan = pendapatan − pengeluaran
/// (perkiraan kas, bukan laba akuntansi).
List<DaySummary> summarizeByDay(List<TxRecord> records) {
  final byDay = <DateTime, List<TxRecord>>{};
  for (final r in records) {
    byDay.putIfAbsent(startOfDay(r.occurredAt), () => []).add(r);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final day in days)
      () {
        var masuk = 0, keluar = 0;
        for (final r in byDay[day]!) {
          if (r.direction == TxDirection.masuk) {
            masuk += r.totalAmount;
          } else {
            keluar += r.totalAmount;
          }
        }
        return (
          day: day,
          count: byDay[day]!.length,
          pendapatan: masuk,
          pengeluaran: keluar,
          keuntungan: masuk - keluar,
        );
      }(),
  ];
}

void _writeRow(Sheet sheet, int row, List<(CellValue, CellStyle?)> cells) {
  for (var col = 0; col < cells.length; col++) {
    final (value, style) = cells[col];
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      value,
      cellStyle: style,
    );
  }
}
