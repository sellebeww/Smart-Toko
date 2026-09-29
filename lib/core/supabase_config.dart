/// Kredensial project Supabase.
///
/// Key ini AMAN ditaruh di kode klien — perlindungan sesungguhnya ada di Row
/// Level Security (RLS) policy yang dipasang di sisi database, bukan di
/// kerahasiaan key ini. Isi dua nilai di bawah dari Project Settings > API
/// setelah project Supabase dibuat (dashboard menyebutnya "anon" / "public"
/// / "publishable" key — semuanya nilai yang sama).
library;

class SupabaseConfig {
  static const String url = 'https://epuhvwdanllhvwwqmcpd.supabase.co';
  static const String publishableKey =
      'sb_publishable_vKVyyMYrIT8ds_73Y3HOWg_dqj_ODsc';
}
