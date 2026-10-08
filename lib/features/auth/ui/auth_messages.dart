/// Pesan galat autentikasi untuk pengguna, dari kode galat Supabase Auth.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String? value) =>
    emailPattern.hasMatch(value?.trim() ?? '')
    ? null
    : 'Masukkan email yang valid';

/// Kode OTP Supabase berupa 6 digit (bisa diatur hingga 10 di dashboard).
String? validateOtp(String? value) =>
    RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Masukkan kode dari email';

String? validateNewPassword(String? value) =>
    (value == null || value.length < 8) ? 'Minimal 8 karakter' : null;

String authErrorMessage(AuthException e) => switch (e.code) {
  'otp_expired' => 'Kode salah atau sudah kedaluwarsa. Minta kode baru.',
  'invalid_credentials' => 'Email atau kata sandi salah',
  'email_not_confirmed' => 'Email belum dikonfirmasi.',
  'user_already_exists' || 'email_exists' => 'Email sudah terdaftar',
  'validation_failed' || 'email_address_invalid' => 'Format email tidak valid',
  'weak_password' =>
    'Kata sandi terlalu lemah. Pakai minimal 8 karakter '
        'dengan campuran huruf dan angka.',
  'same_password' => 'Kata sandi baru harus berbeda dari yang lama.',
  'over_request_rate_limit' ||
  'over_email_send_rate_limit' => 'Terlalu banyak percobaan. Coba lagi nanti.',
  _ when e.statusCode == null => 'Periksa koneksi internet, lalu coba lagi.',
  _ => 'Terjadi gangguan. Silakan coba lagi.',
};
