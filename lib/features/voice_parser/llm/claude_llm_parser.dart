/// Implementasi [LlmParser] di atas Claude Messages API.
///
/// Dart belum punya SDK resmi Anthropic, jadi dipakai HTTP mentah — ini jalur
/// yang memang disarankan untuk bahasa tanpa SDK.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/confidence.dart';
import '../../../core/transaction_kind.dart';
import '../domain/parse_result.dart';
import 'llm_parser.dart';
import 'prompt.dart';

/// Batas atas keyakinan untuk hasil LLM.
///
/// Sengaja ditahan di bawah [Confidence.goodThreshold] supaya hasil LLM selalu
/// jatuh ke pita "perlu dicek". Alasannya: LLM baru dipanggil justru ketika
/// parser deterministik sudah ragu, dan keyakinan yang dilaporkan sendiri oleh
/// model bukan ukuran yang terkalibrasi. Menampilkannya sebagai "yakin" akan
/// menyesatkan pengguna.
const double maxLlmConfidence = 0.79;

typedef ApiKeyProvider = Future<String?> Function();

class ClaudeLlmParser implements LlmParser {
  final ApiKeyProvider apiKeyProvider;
  final http.Client httpClient;
  final Duration timeout;
  final String model;

  ClaudeLlmParser({
    required this.apiKeyProvider,
    required this.httpClient,
    this.timeout = const Duration(seconds: 4),
    this.model = 'claude-opus-5',
  });

  static final Uri _endpoint = Uri.parse(
    'https://api.anthropic.com/v1/messages',
  );

  @override
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  }) async {
    final apiKey = await apiKeyProvider();
    if (apiKey == null || apiKey.isEmpty) {
      return const LlmUnavailable('API key belum diisi di Pengaturan');
    }

    try {
      final response = await httpClient
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode(_requestBody(transcript)),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return LlmUnavailable('HTTP ${response.statusCode}');
      }

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      // stop_reason wajib diperiksa sebelum menyentuh content: penolakan
      // model tetap datang sebagai HTTP 200.
      if (body['stop_reason'] == 'refusal') {
        return const LlmUnavailable('Permintaan ditolak model');
      }

      final input = _extractToolInput(body);
      if (input == null) {
        return const LlmUnavailable('Model tidak mengembalikan tool_use');
      }

      return LlmParsed(_toParseResult(input, transcript, ruleResult));
    } on TimeoutException {
      return const LlmUnavailable('Waktu tunggu habis');
    } catch (e) {
      return LlmUnavailable('Gagal memanggil LLM: $e');
    }
  }

  Map<String, dynamic> _requestBody(String transcript) => {
    'model': model,
    'max_tokens': 1024,
    // Ekstraksi pendek dan pengguna sedang menunggu, jadi effort rendah.
    // Thinking TIDAK dimatikan: dengan thinking mati, model kadang menulis
    // pemanggilan alat sebagai teks biasa alih-alih blok tool_use, yang
    // persis akan mematahkan pembacaan di bawah.
    'output_config': {'effort': 'low'},
    'system': llmSystemPrompt,
    'tools': [
      {
        'name': llmToolName,
        'description': llmToolDescription,
        'strict': true,
        'input_schema': llmToolInputSchema,
      },
    ],
    'tool_choice': {'type': 'tool', 'name': llmToolName},
    'messages': [
      {'role': 'user', 'content': buildUserMessage(transcript)},
    ],
  };

  Map<String, dynamic>? _extractToolInput(Map<String, dynamic> body) {
    final content = body['content'];
    if (content is! List) return null;
    for (final block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'tool_use' &&
          block['name'] == llmToolName) {
        final input = block['input'];
        if (input is Map<String, dynamic>) return input;
      }
    }
    return null;
  }

  ParseResult _toParseResult(
    Map<String, dynamic> input,
    String transcript,
    ParseResult ruleResult,
  ) {
    final reported = (input['keyakinan'] as num?)?.toDouble() ?? 0.5;
    final capped = reported.clamp(0.0, maxLlmConfidence).toDouble();
    final confidence = Confidence(capped);

    final arah = input['arah'] as String?;
    final direction = switch (arah) {
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
        final nama = raw['nama'] as String?;
        final jumlah = (raw['jumlah'] as num?)?.toInt();
        final harga = (raw['harga_satuan'] as num?)?.toInt();
        if (nama == null && harga == null) continue;
        items.add(
          ParsedItem(
            name: nama == null
                ? const ParsedField<String>.missing()
                : ParsedField<String>(value: nama, confidence: confidence),
            qty: ParsedField<int>(value: jumlah ?? 1, confidence: confidence),
            unitPrice: harga == null
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
    );
  }
}
