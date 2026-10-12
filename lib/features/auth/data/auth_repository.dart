/// Jembatan ke Supabase Auth untuk registrasi, login, dan status sesi.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_user.dart';

class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  Stream<AppUser?> authStateChanges() {
    return _client.auth.onAuthStateChange.map(
      (data) => _toAppUser(data.session?.user),
    );
  }

  AppUser? get currentUser => _toAppUser(_client.auth.currentUser);

  Future<AppUser> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    if (response.session == null) {
      // response.user bisa saja tidak null di sini (akunnya memang dibuat),
      // tapi tanpa sesi user belum benar-benar "login". Ini terjadi kalau
      // project mewajibkan konfirmasi email — lihat catatan "Confirm email"
      // di langkah setup.
      throw const AuthException(
        'Akun dibuat, tapi email perlu dikonfirmasi dulu sebelum bisa masuk. Cek kotak masukmu.',
        code: 'email_confirmation_required',
      );
    }
    return _toAppUser(response.user)!;
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _toAppUser(response.user)!;
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Mengirim email berisi kode untuk membuat kata sandi baru. Template
  /// email "Reset Password" di Supabase harus memuat `{{ .Token }}` (lihat
  /// README).
  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  /// Memverifikasi kode dari email reset lalu langsung memasang kata sandi
  /// baru. Verifikasi kode sekaligus membuat sesi, jadi pengguna langsung
  /// masuk setelahnya.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Konfirmasi email pendaftaran dengan kode dari email. Template "Confirm
  /// signup" di Supabase harus memuat `{{ .Token }}`.
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
  }

  Future<void> resendSignupCode(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email.trim());

  /// Mengirim kode lewat SMS. Akun dibuat otomatis bila nomor ini baru.
  /// [phone] dalam format internasional tanpa + (628...).
  Future<void> sendPhoneCode(String phone) =>
      _client.auth.signInWithOtp(phone: '+$phone');

  Future<AppUser> verifyPhoneCode({
    required String phone,
    required String code,
  }) async {
    final response = await _client.auth.verifyOTP(
      phone: '+$phone',
      token: code.trim(),
      type: OtpType.sms,
    );
    return _toAppUser(response.user)!;
  }

  AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(uid: user.id, email: user.email, phone: user.phone);
  }
}
