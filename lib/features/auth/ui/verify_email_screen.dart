/// Konfirmasi email pendaftaran dengan kode yang dikirim ke email.
///
/// Dipakai bila project Supabase mewajibkan konfirmasi email. Setelah kode
/// benar, sesi aktif dan gerbang login di app.dart langsung membuka aplikasi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import 'auth_messages.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;

  /// true bila kode belum dikirim (mis. dibuka dari layar masuk), sehingga
  /// layar ini langsung meminta kode baru.
  final bool sendOnOpen;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.sendOnOpen = false,
  });

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.sendOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resend());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Terjadi gangguan. Silakan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final repository = ref.read(authRepositoryProvider);
    await _guard(
      () => repository.verifySignupCode(email: widget.email, code: _code.text),
    );
  }

  Future<void> _resend() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    await _guard(() async {
      await ref.read(authRepositoryProvider).resendSignupCode(widget.email);
      messenger.showSnackBar(
        const SnackBar(content: Text('Kode baru dikirim ke email')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Konfirmasi email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Kami mengirim kode ke ${widget.email}. Masukkan kodenya '
                  'untuk mengaktifkan akun. Periksa juga folder spam.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(
                    labelText: 'Kode dari email',
                  ),
                  validator: validateOtp,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Konfirmasi'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Kirim ulang kode'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
