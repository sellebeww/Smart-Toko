/// Kontrak lapisan kedua parser.
///
/// PERHATIAN PRIVASI: implementasi mana pun dari [LlmParser] mengirim transkrip
/// ucapan pengguna KELUAR dari perangkat. Karena itu pemanggilnya wajib
/// memastikan pengguna sudah mengaktifkannya lewat sakelar tersendiri — bukan
/// dibonceng ke sakelar sinkronisasi — dan fitur ini default MATI.
library;

import '../domain/parse_result.dart';

sealed class LlmParseOutcome {
  const LlmParseOutcome();
}

class LlmParsed extends LlmParseOutcome {
  final ParseResult result;
  const LlmParsed(this.result);
}

/// LLM tidak dipakai atau gagal. Pemanggil harus meneruskan hasil aturan apa
/// adanya — jalur ini tidak pernah boleh menggagalkan pencatatan.
class LlmUnavailable extends LlmParseOutcome {
  final String reason;
  const LlmUnavailable(this.reason);

  @override
  String toString() => 'LlmUnavailable($reason)';
}

abstract class LlmParser {
  /// Mencoba memperbaiki [ruleResult] untuk [transcript].
  ///
  /// Tidak boleh melempar: kegagalan apa pun dikembalikan sebagai
  /// [LlmUnavailable].
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  });
}

/// Implementasi default saat fitur LLM dimatikan atau belum dikonfigurasi.
class DisabledLlmParser implements LlmParser {
  final String reason;
  const DisabledLlmParser([this.reason = 'Parsing LLM tidak aktif']);

  @override
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  }) async => LlmUnavailable(reason);
}

/// Memeriksa sakelar pengguna tepat sebelum memanggil [delegate].
///
/// Pemeriksaan sengaja dilakukan pada saat pemanggilan, bukan saat perakitan
/// objek: kalau dicek sekali di awal, mematikan sakelar di Pengaturan tidak
/// akan berpengaruh sampai aplikasi dimulai ulang — dan selama itu transkrip
/// masih terkirim keluar.
class GatedLlmParser implements LlmParser {
  final Future<bool> Function() isEnabled;
  final LlmParser delegate;
  final String disabledReason;

  const GatedLlmParser({
    required this.isEnabled,
    required this.delegate,
    this.disabledReason = 'Parsing LLM tidak aktif',
  });

  @override
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  }) async {
    if (!await isEnabled()) return LlmUnavailable(disabledReason);
    return delegate.refine(transcript: transcript, ruleResult: ruleResult);
  }
}
