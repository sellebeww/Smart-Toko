/// Menyimpan berkas Excel ke folder sementara lalu membuka lembar bagikan
/// (WhatsApp, Drive, email, dsb.).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../contacts/contacts_providers.dart';
import '../stores/stores_providers.dart';
import '../transactions/domain/transaction_record.dart';
import 'excel_exporter.dart';

const String _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Semua transaksi toko aktif, dari catatan pertama sampai hari ini.
Future<void> exportAllTransactions(BuildContext context, WidgetRef ref) async {
  final records = await ref
      .read(transactionRepositoryProvider)
      .listBetween(
        storeId: ref.read(activeStoreIdProvider)!,
        from: DateTime.fromMillisecondsSinceEpoch(0),
        to: DateTime.now().add(const Duration(days: 1)),
      );
  if (!context.mounted) return;
  if (records.isEmpty) {
    _tell(context, 'Belum ada transaksi untuk diekspor.');
    return;
  }
  // Terurut terbaru dulu.
  await exportTransactions(
    context,
    ref,
    records: records,
    from: records.last.occurredAt,
    toInclusive: records.first.occurredAt,
  );
}

/// [from] dan [toInclusive] hanya dipakai untuk nama berkas.
Future<void> exportTransactions(
  BuildContext context,
  WidgetRef ref, {
  required List<TxRecord> records,
  required DateTime from,
  required DateTime toInclusive,
}) async {
  if (records.isEmpty) {
    _tell(context, 'Tidak ada transaksi pada filter ini.');
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

  try {
    final storeName = ref.read(activeStoreProvider).value?.name ?? 'Toko';
    final contactNames = await ref.read(contactNamesProvider.future);
    final bytes = buildTransactionsWorkbook(
      records,
      contactNames: contactNames,
    );
    final name = exportFileName(
      storeName: storeName,
      from: from,
      to: toInclusive,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: _xlsxMime, name: name)],
        subject: 'Laporan $storeName',
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    if (context.mounted) _tell(context, 'Gagal membuat berkas Excel.');
  }
}

void _tell(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
