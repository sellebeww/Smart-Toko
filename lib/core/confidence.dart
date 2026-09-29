/// Tipe keyakinan bersama, dipakai parser maupun lapisan transaksi.
///
/// Pure Dart — tidak boleh mengimpor Flutter.
library;

enum ConfidenceBand {
  /// Tampilkan normal.
  good,

  /// Sorot dan minta pengguna mengecek ulang.
  check,

  /// Kosongkan nilainya dan arahkan fokus ke field ini.
  poor,
}

/// Tingkat keyakinan sebuah nilai.
///
/// [Confidence.unknown] sengaja dibedakan dari keyakinan rendah. Sebagian
/// engine STT Android selalu melaporkan 0.0 walau hasilnya sudah final;
/// memetakannya ke [ConfidenceBand.poor] akan membuat SELURUH field selalu
/// kosong di perangkat tersebut dan fitur voice jadi tidak berguna. Karena itu
/// "tidak diketahui" jatuh ke [ConfidenceBand.check].
class Confidence implements Comparable<Confidence> {
  final double? value;

  const Confidence(double this.value);
  const Confidence.unknown() : value = null;

  static const double goodThreshold = 0.80;
  static const double checkThreshold = 0.50;

  bool get isUnknown => value == null;

  ConfidenceBand get band {
    final v = value;
    if (v == null) return ConfidenceBand.check;
    if (v >= goodThreshold) return ConfidenceBand.good;
    if (v >= checkThreshold) return ConfidenceBand.check;
    return ConfidenceBand.poor;
  }

  /// Menggabungkan keyakinan STT dengan kekuatan kecocokan aturan.
  ///
  /// Bila salah satu tidak diketahui, hasilnya ikut tidak diketahui — menebak
  /// angka di sini akan menyamarkan ketidakpastian yang justru ingin
  /// ditunjukkan ke pengguna.
  Confidence combine(Confidence other) {
    final a = value;
    final b = other.value;
    if (a == null || b == null) return const Confidence.unknown();
    return Confidence(a * b);
  }

  @override
  int compareTo(Confidence other) =>
      (value ?? checkThreshold).compareTo(other.value ?? checkThreshold);

  @override
  String toString() => isUnknown ? 'Confidence(unknown)' : 'Confidence($value)';
}
