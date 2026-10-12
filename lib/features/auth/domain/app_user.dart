/// Representasi pengguna yang sudah login, dilepas dari detail Supabase.
library;

class AppUser {
  final String uid;
  final String? email;

  /// Nomor HP (format internasional tanpa +) untuk akun yang masuk lewat SMS.
  final String? phone;

  const AppUser({required this.uid, this.email, this.phone});

  /// Penanda pencatat transaksi dan anggota toko: email, atau nomor HP bila
  /// akunnya tidak punya email.
  String? get identity {
    if (email != null && email!.isNotEmpty) return email;
    if (phone != null && phone!.isNotEmpty) return '+$phone';
    return null;
  }
}
