/// Pencatatan ucapan yang gagal/ragu diurai.
///
/// Ini satu-satunya cara aturan parser bisa diperbaiki berdasarkan bukti, bukan
/// tebakan. Catatannya LOKAL saja; mengirimkannya keluar perangkat butuh
/// persetujuan terpisah karena transkrip bisa memuat informasi pribadi.
library;

enum ParseFailureReason {
  /// Tidak ada barang yang berhasil dikenali.
  noItems,

  /// Ada token yang tidak terpetakan ke field mana pun.
  unmatchedTokens,

  /// Keyakinan keseluruhan di bawah ambang.
  lowConfidence,

  /// Arah transaksi tidak tersebut.
  missingDirection,
}

class ParseFailure {
  final String transcript;
  final double? sttConfidence;
  final String parserVersion;
  final Set<ParseFailureReason> reasons;
  final List<String> unmatchedTokens;
  final DateTime occurredAt;

  const ParseFailure({
    required this.transcript,
    required this.sttConfidence,
    required this.parserVersion,
    required this.reasons,
    required this.unmatchedTokens,
    required this.occurredAt,
  });

  String get reasonLabel => reasons.map((r) => r.name).join(',');
}

abstract class ParseFailureLogger {
  Future<void> record(ParseFailure failure);
}

class NoopParseFailureLogger implements ParseFailureLogger {
  const NoopParseFailureLogger();

  @override
  Future<void> record(ParseFailure failure) async {}
}

/// Penampung di memori, dipakai pengujian dan mode pengembangan.
class InMemoryParseFailureLogger implements ParseFailureLogger {
  final List<ParseFailure> entries = [];

  @override
  Future<void> record(ParseFailure failure) async => entries.add(failure);
}
