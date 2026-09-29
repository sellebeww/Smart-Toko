/// Representasi pengguna yang sudah login, dilepas dari detail Supabase.
library;

class AppUser {
  final String uid;
  final String? email;

  const AppUser({required this.uid, this.email});
}
