/// Layar masuk dengan email dan kata sandi.
///
/// Ditampilkan sebagai gerbang paling luar aplikasi (lihat app/app.dart) saat
/// belum ada sesi Supabase Auth aktif. Setelah login berhasil, gerbang itu
/// yang mengganti layar — layar ini tidak melakukan navigasi sendiri.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/ui/brand.dart';
import 'auth_messages.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _needsConfirmation = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
      _needsConfirmation = false;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorText = authErrorMessage(e);
          _needsConfirmation = e.code == 'email_not_confirmed';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Terjadi gangguan. Silakan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandHeader(),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              SmartTokoTheme.forest,
                              SmartTokoTheme.green,
                            ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: SmartTokoTheme.lime,
                              size: 28,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Usaha jalan.\nCatatan rapi.',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Catat dengan suara, pantau penjualan,\ndan kelola stok dalam satu tempat.',
                              style: TextStyle(
                                color: Color(0xFFE2F1D7),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Selamat datang kembali',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Masuk untuk mengelola tokomu.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                          hintText: 'nama@email.com',
                        ),
                        validator: validateEmail,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Kata sandi',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Tampilkan kata sandi'
                                : 'Sembunyikan kata sandi',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            (value == null || value.length < 6)
                            ? 'Minimal 6 karakter'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ResetPasswordScreen(
                                      initialEmail: _emailController.text
                                          .trim(),
                                    ),
                                  ),
                                ),
                          child: const Text('Lupa kata sandi?'),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorText!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      if (_needsConfirmation)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VerifyEmailScreen(
                                email: _emailController.text.trim(),
                                sendOnOpen: true,
                              ),
                            ),
                          ),
                          child: const Text('Masukkan kode konfirmasi'),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Masuk'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                        child: const Text('Belum punya akun? Daftar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
