/// Lupa kata sandi: kirim kode ke email, lalu buat kata sandi baru dengan
/// kode itu langsung di aplikasi. Tidak memakai tautan, jadi tidak
/// bergantung pada deep link atau halaman web terpisah.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import 'auth_messages.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
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

  Future<void> _send() async {
    if (_busy || !_emailFormKey.currentState!.validate()) return;
    await _request();
  }

  Future<void> _resend() async {
    if (_busy) return;
    await _request();
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Kode baru dikirim')));
    }
  }

  Future<void> _request() async {
    await _guard(() async {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      // Supabase sendiri sudah menjaga kerahasiaan apakah email terdaftar:
      // responsnya sama saja baik email ada atau tidak.
      if (mounted) setState(() => _sent = true);
    });
  }

  Future<void> _reset() async {
    if (_busy || !_codeFormKey.currentState!.validate()) return;
    final repository = ref.read(authRepositoryProvider);
    // Begitu kode terverifikasi, sesi aktif dan gerbang login membuka layar
    // utama — layar ini ikut tertutup dengan sendirinya.
    await _guard(
      () => repository.resetPasswordWithCode(
        email: _email.text,
        code: _code.text,
        newPassword: _password.text,
      ),
    );
  }

  Widget _errorText(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      _error!,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _progress(String label) => _busy
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atur ulang kata sandi')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent ? _codeStep(context) : _emailStep(context),
        ),
      ),
    );
  }

  Widget _emailStep(BuildContext context) => Form(
    key: _emailFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.lock_reset,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        const Text(
          'Masukkan email akunmu. Kami akan mengirim kode untuk membuat kata sandi baru.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _send(),
          decoration: const InputDecoration(labelText: 'Email'),
          validator: validateEmail,
        ),
        if (_error != null) _errorText(context),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _progress('Kirim kode'),
        ),
      ],
    ),
  );

  Widget _codeStep(BuildContext context) => Form(
    key: _codeFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Jika ${_email.text.trim()} terdaftar, kode akan dikirim ke sana. '
          'Periksa kotak masuk dan folder spam, lalu masukkan kodenya di bawah.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Kode dari email'),
          validator: validateOtp,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Kata sandi baru',
            suffixIcon: IconButton(
              tooltip: _obscure
                  ? 'Tampilkan kata sandi'
                  : 'Sembunyikan kata sandi',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: validateNewPassword,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirm,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: const InputDecoration(
            labelText: 'Ulangi kata sandi baru',
          ),
          validator: (value) =>
              value != _password.text ? 'Kata sandi tidak sama' : null,
        ),
        if (_error != null) _errorText(context),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _reset,
          child: _progress('Simpan kata sandi baru'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Kirim ulang kode'),
        ),
      ],
    ),
  );
}
