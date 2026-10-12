/// Satu jalur membuka layar konfirmasi dan menyimpan hasilnya, dipakai untuk
/// catatan baru (layar utama) maupun koreksi (detail transaksi).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/auth_providers.dart';
import '../../contacts/ui/contact_picker_sheet.dart';
import '../domain/confirmed_draft.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_record.dart';
import 'confirmation_sheet.dart';

/// Mengembalikan transaksi yang tersimpan, atau null bila dibatalkan.
///
/// Bila [replaceId] diisi, transaksi itu diganti oleh hasil koreksi dalam
/// satu transaksi basis data.
Future<TxRecord?> showTransactionEditor(
  BuildContext context,
  WidgetRef ref, {
  required TransactionDraft draft,
  String? replaceId,
  String? initialContactName,
}) async {
  TxRecord? saved;

  Future<void> persist(ConfirmedDraft confirmed) async {
    final repository = ref.read(transactionRepositoryProvider);
    final storeId = ref.read(activeStoreIdProvider)!;
    final recordedBy = ref.read(authStateChangesProvider).value?.identity;
    saved = replaceId == null
        ? await repository.save(
            confirmed,
            storeId: storeId,
            recordedBy: recordedBy,
          )
        : await repository.replace(
            replaceId,
            confirmed,
            storeId: storeId,
            recordedBy: recordedBy,
          );
    ref.read(dataRevisionProvider.notifier).bump();
    if (context.mounted) Navigator.of(context).pop();
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => ConfirmationSheet(
      draft: draft,
      onConfirm: persist,
      pickContact: (kind) => showContactPicker(context, kind),
      initialContactName: initialContactName,
      title: replaceId == null
          ? 'Periksa dulu sebelum disimpan'
          : 'Koreksi transaksi',
    ),
  );

  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(replaceId == null ? 'Tersimpan' : 'Terkoreksi')),
    );
  }
  return saved;
}
