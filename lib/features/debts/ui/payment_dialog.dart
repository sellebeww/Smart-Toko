/// Dialog mencatat pembayaran kasbon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/format.dart';
import '../../transactions/domain/transaction_record.dart';
import '../data/debt_repository.dart';
import '../debts_providers.dart';

/// Mengembalikan true bila pembayaran tercatat.
Future<bool> showPaymentDialog(
  BuildContext context,
  WidgetRef ref, {
  required TxRecord record,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PaymentDialog(record: record),
  );
  if (saved == true) {
    ref.read(dataRevisionProvider.notifier).bump();
    return true;
  }
  return false;
}

class _PaymentDialog extends ConsumerStatefulWidget {
  final TxRecord record;
  const _PaymentDialog({required this.record});

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: formatNumber(widget.record.outstanding),
  );
  final TextEditingController _note = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupiahInput(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Isi jumlah yang dibayar.');
      return;
    }
    if (amount > widget.record.outstanding) {
      setState(
        () => _error =
            'Melebihi sisa ${formatRupiah(widget.record.outstanding)}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(debtRepositoryProvider)
          .addPayment(
            storeId: widget.record.storeId,
            transactionId: widget.record.id,
            amount: amount,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on DebtException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pembayaran belum tersimpan. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = widget.record.outstanding;
    return AlertDialog(
      title: const Text('Catat pembayaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sisa: ${formatRupiah(outstanding)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Dibayar sekarang',
                prefixText: 'Rp ',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _amount.text = formatNumber(outstanding),
                child: const Text('Lunasi semua'),
              ),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
