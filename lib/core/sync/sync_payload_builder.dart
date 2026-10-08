/// Satu-satunya tempat data disiapkan untuk dikirim keluar perangkat.
///
/// Semua payload — entitas apa pun, sekarang maupun nanti — wajib melewati
/// [build]. Penyaringan field identitas dilakukan di sini sebagai langkah
/// TERAKHIR dan tanpa syarat, sehingga penambahan entitas baru di kemudian hari
/// tidak bisa diam-diam membocorkan data KTP hanya karena penulisnya lupa.
library;

import '../../features/transactions/domain/transaction_record.dart';

/// Field yang tidak pernah ikut keluar perangkat (sinkron maupun cadangan) tanpa persetujuan identitas
/// yang terpisah dan eksplisit.
const Set<String> identityFieldNames = {
  'ktp_number',
  'ktp_image_path',
  'ktp_image',
  'nib',
  'nib_number',
  'owner_name',
  'owner_address',
  'owner_birth_date',
  // Email akun pencatat: cukup untuk laporan di perangkat, tidak perlu ikut
  // ke luar tanpa persetujuan.
  'recorded_by',
};

class SyncPayloadBuilder {
  const SyncPayloadBuilder();

  /// [identityConsent] hanya boleh true bila pengguna menyetujui layar
  /// persetujuan data identitas — bukan sekadar menyalakan cadangan.
  Map<String, Object?> build(
    Map<String, Object?> raw, {
    required bool identityConsent,
  }) {
    if (identityConsent) return Map<String, Object?>.unmodifiable(raw);
    return Map<String, Object?>.unmodifiable(redactIdentity(raw));
  }

  Map<String, Object?> buildTransaction(
    TxRecord record, {
    required bool identityConsent,
  }) => build({
    ...record.toRow(),
    'items': [for (final item in record.items) item.toRow()],
  }, identityConsent: identityConsent);

  /// Membuang field identitas secara rekursif, termasuk di dalam daftar dan
  /// peta bersarang.
  static Map<String, Object?> redactIdentity(Map<String, Object?> raw) {
    final result = <String, Object?>{};
    raw.forEach((key, value) {
      if (identityFieldNames.contains(key)) return;
      result[key] = _redactValue(value);
    });
    return result;
  }

  static Object? _redactValue(Object? value) {
    if (value is Map<String, Object?>) return redactIdentity(value);
    if (value is Map) {
      return redactIdentity(value.map((k, v) => MapEntry('$k', v)));
    }
    if (value is List) return [for (final item in value) _redactValue(item)];
    return value;
  }
}
