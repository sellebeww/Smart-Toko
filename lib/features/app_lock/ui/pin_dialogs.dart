/// Dialog mengatur, mengubah, dan mematikan PIN dari Pengaturan.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_lock_controller.dart';
import '../pin_hasher.dart';

String blockedText(DateTime? until, DateTime now) {
  final seconds = until == null ? 30 : until.difference(now).inSeconds + 1;
  final wait = seconds >= 60
      ? '${(seconds / 60).ceil()} menit'
      : '$seconds detik';
  return 'Terlalu banyak percobaan salah. Coba lagi dalam $wait.';
}

/// Satu isian PIN pada dialog.
class _PinField {
  final String label;
  final TextEditingController controller = TextEditingController();
  _PinField(this.label);
}

/// Dialog berisi beberapa isian PIN. [onSubmit] menerima isinya dan
/// mengembalikan pesan kesalahan, atau null bila berhasil (dialog tertutup).
Future<bool> _showPinForm(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required String confirmLabel,
  required Future<String?> Function(List<String> pins) onSubmit,
  String? hint,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _PinFormDialog(
      title: title,
      labels: labels,
      confirmLabel: confirmLabel,
      onSubmit: onSubmit,
      hint: hint,
    ),
  );
  return result == true;
}

class _PinFormDialog extends StatefulWidget {
  final String title;
  final List<String> labels;
  final String confirmLabel;
  final String? hint;
  final Future<String?> Function(List<String> pins) onSubmit;

  const _PinFormDialog({
    required this.title,
    required this.labels,
    required this.confirmLabel,
    required this.onSubmit,
    this.hint,
  });

  @override
  State<_PinFormDialog> createState() => _PinFormDialogState();
}

class _PinFormDialogState extends State<_PinFormDialog> {
  late final List<_PinField> _fields = [
    for (final label in widget.labels) _PinField(label),
  ];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final field in _fields) {
      field.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit([
      for (final f in _fields) f.controller.text,
    ]);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[
            Text(widget.hint!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _fields[i].controller,
                autofocus: i == 0,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: maxPinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _fields[i].label,
                  counterText: '',
                ),
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// Kesalahan umum untuk PIN baru, atau null bila boleh dipakai.
String? validateNewPin(String pin, String repeat) {
  if (!isValidPin(pin)) {
    return 'PIN harus $minPinLength sampai $maxPinLength angka.';
  }
  if (isWeakPin(pin)) return 'PIN terlalu mudah ditebak (mis. 1234 atau 0000).';
  if (pin != repeat) return 'Pengulangan PIN tidak sama.';
  return null;
}

Future<bool> showEnablePin(BuildContext context, WidgetRef ref) {
  final controller = ref.read(appLockControllerProvider.notifier);
  return _showPinForm(
    context,
    title: 'Pasang PIN',
    hint:
        'PIN mengunci tampilan aplikasi saat ditinggalkan lebih dari satu '
        'menit. Ini bukan enkripsi data.',
    labels: const ['PIN baru', 'Ulangi PIN'],
    confirmLabel: 'Pasang',
    onSubmit: (pins) async {
      final error = validateNewPin(pins[0], pins[1]);
      if (error != null) return error;
      await controller.enable(pins[0]);
      return null;
    },
  );
}

Future<bool> showDisablePin(BuildContext context, WidgetRef ref) {
  final controller = ref.read(appLockControllerProvider.notifier);
  return _showPinForm(
    context,
    title: 'Matikan kunci PIN',
    labels: const ['PIN saat ini'],
    confirmLabel: 'Matikan',
    onSubmit: (pins) async {
      final result = await controller.disable(pins[0]);
      return _message(ref, result);
    },
  );
}

Future<bool> showChangePin(BuildContext context, WidgetRef ref) {
  final controller = ref.read(appLockControllerProvider.notifier);
  return _showPinForm(
    context,
    title: 'Ubah PIN',
    labels: const ['PIN saat ini', 'PIN baru', 'Ulangi PIN baru'],
    confirmLabel: 'Ubah',
    onSubmit: (pins) async {
      final error = validateNewPin(pins[1], pins[2]);
      if (error != null) return error;
      final result = await controller.changePin(pins[0], pins[1]);
      return _message(ref, result);
    },
  );
}

String? _message(WidgetRef ref, UnlockResult result) => switch (result) {
  UnlockResult.success => null,
  UnlockResult.wrong => 'PIN saat ini salah.',
  UnlockResult.blocked => blockedText(
    ref.read(appLockControllerProvider).value?.blockedUntil,
    ref.read(appLockClockProvider)(),
  ),
};
