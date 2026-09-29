import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      // Supabase sendiri sudah menjaga kerahasiaan apakah email terdaftar:
      // responsnya sama saja baik email ada atau tidak.
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.code) {
          'validation_failed' ||
          'email_address_invalid' => 'Masukkan email yang valid.',
          'over_email_send_rate_limit' || 'over_request_rate_limit' =>
            'Terlalu banyak percobaan. Coba lagi nanti.',
          _ when e.statusCode == null =>
            'Periksa koneksi internet, lalu coba lagi.',
          _ => 'Belum bisa mengirim tautan. Silakan coba lagi.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Terjadi gangguan. Silakan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atur ulang kata sandi')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _sent ? Icons.mark_email_read_outlined : Icons.lock_reset,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  _sent
                      ? 'Jika email ini terdaftar, tautan pengaturan ulang akan dikirim. Periksa kotak masuk dan folder spam.'
                      : 'Masukkan email akunmu. Kami akan mengirim tautan untuk membuat kata sandi baru.',
                ),
                const SizedBox(height: 24),
                if (!_sent) ...[
                  TextFormField(
                    controller: _email,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _send(),
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Masukkan email yang valid',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kirim tautan'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kembali ke masuk'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
