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

  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(uid: user.id, email: user.email);
  }
}
