/// Masuk dengan nomor HP dan kode SMS. Hanya tampil bila
/// [SupabaseConfig.phoneLogin] menyala.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../debts/reminder.dart' show normalizeIndonesianPhone;

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = normalizeIndonesianPhone(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Nomor HP belum benar. Contoh: 0812 3456 7890');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPhoneCode(phone);
      if (mounted) setState(() => _sentTo = phone);
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.statusCode == '429'
              ? 'Terlalu sering meminta kode. Tunggu sebentar.'
              : 'Kode belum bisa dikirim. Coba lagi nanti.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Periksa koneksi internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final phone = _sentTo;
    if (phone == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhoneCode(phone: phone, code: _code.text);
      // Gerbang akun di app.dart berpindah sendiri setelah sesi terbentuk.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on AuthException {
      if (mounted) setState(() => _error = 'Kode salah atau kedaluwarsa.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Periksa koneksi internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk dengan nomor HP')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _phone,
            enabled: !sent && !_busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Nomor HP',
              hintText: '0812 3456 7890',
            ),
          ),
          if (sent) ...[
            const SizedBox(height: 16),
            Text('Kode dikirim lewat SMS ke +$_sentTo.'),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Kode SMS'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (sent ? _verify : _send),
            child: Text(sent ? 'Masuk' : 'Kirim kode'),
          ),
          if (sent)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _sentTo = null;
                      _code.clear();
                    }),
              child: const Text('Ganti nomor'),
            ),
        ],
      ),
    );
  }
}
