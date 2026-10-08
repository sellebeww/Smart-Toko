import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/transaction_kind.dart';
import '../../../core/ui/figma_icon.dart';
import '../domain/transaction_draft.dart';

Future<TransactionDraft?> showTextEntry(BuildContext context) =>
    showModalBottomSheet<TransactionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TextEntrySheet(),
    );

/// Teks alami tetap menghasilkan draf; tidak menyimpan tanpa konfirmasi.
class TextEntrySheet extends ConsumerStatefulWidget {
  const TextEntrySheet({super.key});

  @override
  ConsumerState<TextEntrySheet> createState() => _TextEntrySheetState();
}

class _TextEntrySheetState extends ConsumerState<TextEntrySheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    if (_busy) return;
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Tulis transaksinya terlebih dahulu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(parserPipelineProvider).parse(text);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(TransactionDraft.fromParseResult(result, source: TxSource.manual));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Belum berhasil membaca kalimat. Coba lagi atau isi formulir manual.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Catat transaksi',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text('Ceritakan saja, kami bantu rapikan.'),
          const SizedBox(height: 24),
          TextField(
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Apa transaksinya?',
              alignLabelWithHint: true,
              hintText: 'Beli ayam 5 kg Rp200.000',
              errorText: _error,
              helperText: 'Tulis bahan atau menu, jumlah, dan harga.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _parse,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FigmaIcon('cd636'),
            label: Text(_busy ? 'Membaca transaksi…' : 'Periksa transaksi'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop(TransactionDraft.manual()),
            child: const Text('Isi formulir manual'),
          ),
          const Text(
            'Belum disimpan · Stok berubah setelah kamu konfirmasi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF718077)),
          ),
        ],
      ),
    ),
  );
}
