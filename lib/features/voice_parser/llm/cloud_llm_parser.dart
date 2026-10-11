/// Implementasi [LlmParser] lewat Edge Function `parse-transaction`.
///
/// Aplikasi tidak pernah memegang kunci API model. Yang dikirim hanya
/// transkrip; prompt, skema keluaran, pemilihan model, dan pembatasan kuota
/// per pengguna ada di sisi server (supabase/functions/parse-transaction).
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/confidence.dart';
import '../../../core/transaction_kind.dart';
import '../domain/parse_result.dart';
import 'llm_parser.dart';

/// Batas atas keyakinan untuk hasil LLM.
///
/// Sengaja ditahan di bawah [Confidence.goodThreshold] supaya hasil LLM selalu
/// jatuh ke pita "perlu dicek". Alasannya: LLM baru dipanggil justru ketika
/// parser deterministik sudah ragu, dan keyakinan yang dilaporkan sendiri oleh
/// model bukan ukuran yang terkalibrasi. Menampilkannya sebagai "yakin" akan
/// menyesatkan pengguna.
const double maxLlmConfidence = 0.79;

const String parseTransactionFunction = 'parse-transaction';

/// Mengirim transkrip ke server dan mengembalikan objek `result` dari
/// responsnya. Dipisah supaya pemetaan hasil bisa diuji tanpa jaringan.
typedef LlmInvoker = Future<Map<String, dynamic>> Function(String transcript);

LlmInvoker supabaseLlmInvoker(SupabaseClient client) => (transcript) async {
  final response = await client.functions.invoke(
    parseTransactionFunction,
    body: {'transcript': transcript},
  );
  final data = response.data;
  if (data is Map<String, dynamic> && data['result'] is Map<String, dynamic>) {
    return data['result'] as Map<String, dynamic>;
  }
  throw const FormatException('Respons server tanpa hasil');
};

class CloudLlmParser implements LlmParser {
  final LlmInvoker invoke;
  final Duration timeout;

  CloudLlmParser({
    required this.invoke,
    this.timeout = const Duration(seconds: 12),
  });

  @override
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  }) async {
    try {
      final input = await invoke(transcript).timeout(timeout);
      return LlmParsed(toParseResult(input, transcript, ruleResult));
    } on TimeoutException {
      return const LlmUnavailable('Waktu tunggu habis');
    } on FunctionException catch (e) {
      return LlmUnavailable(switch (e.status) {
        429 => 'Batas harian bantuan AI sudah tercapai',
        401 || 403 => 'Sesi berakhir, silakan masuk lagi',
        422 => 'Permintaan ditolak model',
        _ => 'Server AI bermasalah (${e.status})',
      });
    } catch (e) {
      return LlmUnavailable('Gagal memanggil bantuan AI: $e');
    }
  }

  static ParseResult toParseResult(
    Map<String, dynamic> input,
    String transcript,
    ParseResult ruleResult,
  ) {
    final reported = (input['keyakinan'] as num?)?.toDouble() ?? 0.5;
    final capped = reported.clamp(0.0, maxLlmConfidence).toDouble();
    final confidence = Confidence(capped);

    final direction = switch (input['arah']) {
      'masuk' => ParsedField<TxDirection>(
        value: TxDirection.masuk,
        confidence: confidence,
      ),
      'keluar' => ParsedField<TxDirection>(
        value: TxDirection.keluar,
        confidence: confidence,
      ),
      _ => const ParsedField<TxDirection>.missing(),
    };

    final rawItems = input['barang'];
    final items = <ParsedItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final nama = (raw['nama'] as String?)?.trim();
        final jumlah = (raw['jumlah'] as num?)?.toInt();
        final harga = (raw['harga_satuan'] as num?)?.toInt();
        final hasName = nama != null && nama.isNotEmpty;
        if (!hasName && harga == null) continue;
        items.add(
          ParsedItem(
            name: hasName
                ? ParsedField<String>(value: nama, confidence: confidence)
                : const ParsedField<String>.missing(),
            qty: ParsedField<int>(
              value: (jumlah == null || jumlah <= 0) ? 1 : jumlah,
              confidence: confidence,
            ),
            unitPrice: (harga == null || harga < 0)
                ? const ParsedField<int>.missing()
                : ParsedField<int>(value: harga, confidence: confidence),
          ),
        );
      }
    }

    return ParseResult(
      transcript: transcript,
      parserVersion: '${ruleResult.parserVersion}+llm',
      source: ParseSource.llm,
      direction: direction,
      items: items,
      totalAmount: const ParsedField.missing(),
      unmatchedTokens: const [],
      // Server AI tidak diminta mengenali kasbon; petunjuk dari parser
      // lokal tetap dipakai.
      onCredit: ruleResult.onCredit,
      dueInDays: ruleResult.dueInDays,
    );
  }
}
