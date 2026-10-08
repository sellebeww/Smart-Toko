/// Kredensial project Supabase.
///
/// Key ini AMAN ditaruh di kode klien — perlindungan sesungguhnya ada di Row
/// Level Security, hak kolom, dan fungsi di supabase/setup.sql, bukan di
/// kerahasiaan key ini. Nilainya bisa diganti saat build untuk project lain
/// (mis. staging):
///
///   flutter build appbundle \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
library;

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://epuhvwdanllhvwwqmcpd.supabase.co',
  );
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_vKVyyMYrIT8ds_73Y3HOWg_dqj_ODsc',
  );

  /// Bantuan AI butuh Edge Function `parse-transaction` yang sudah di-deploy
  /// (lihat README). Selama belum, fitur ini disembunyikan dan tidak pernah
  /// mengirim transkrip ke mana pun. Nyalakan saat build dengan
  /// `--dart-define=AI_ASSIST=true`.
  static const bool aiAssist = bool.fromEnvironment('AI_ASSIST');

  /// URL publik kebijakan privasi (wajib untuk Play Store). Isi saat build
  /// dengan `--dart-define=PRIVACY_URL=https://...`; selama kosong, menu
  /// "Kebijakan privasi" tidak ditampilkan.
  static const String privacyUrl = String.fromEnvironment('PRIVACY_URL');
}
