/// Tes kebijakan eskalasi ke LLM.
///
/// Yang dijaga di sini terutama adalah janji privasi: transkrip TIDAK boleh
/// keluar perangkat kecuali aturan benar-benar mentok, perangkat daring, dan
/// pengguna sudah menyalakannya.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/core/confidence.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/voice_parser/domain/parse_result.dart';
import 'package:smart_toko/features/voice_parser/llm/llm_parser.dart';
import 'package:smart_toko/features/voice_parser/logging/parse_failure_logger.dart';
import 'package:smart_toko/features/voice_parser/parser_pipeline.dart';

class RecordingLlmParser implements LlmParser {
  int calls = 0;
  final List<String> seenTranscripts = [];

  @override
  Future<LlmParseOutcome> refine({
    required String transcript,
    required ParseResult ruleResult,
  }) async {
    calls++;
    seenTranscripts.add(transcript);
    return LlmParsed(
      ParseResult(
        transcript: transcript,
        parserVersion: '${ruleResult.parserVersion}+llm',
        source: ParseSource.llm,
        direction: const ParsedField(
          value: TxDirection.masuk,
          confidence: Confidence(0.79),
        ),
        items: const [
          ParsedItem(
            name: ParsedField(value: 'teh botol', confidence: Confidence(0.79)),
            qty: ParsedField(value: 3, confidence: Confidence(0.79)),
            unitPrice: ParsedField(value: 15000, confidence: Confidence(0.79)),
          ),
        ],
        totalAmount: const ParsedField.missing(),
        unmatchedTokens: const [],
      ),
    );
  }
}

void main() {
  late RecordingLlmParser llm;
  late InMemoryParseFailureLogger log;

  setUp(() {
    llm = RecordingLlmParser();
    log = InMemoryParseFailureLogger();
  });

  ParserPipeline pipeline({required bool online, LlmParser? parser}) =>
      ParserPipeline(
        llmParser: parser ?? llm,
        failureLogger: log,
        isOnline: () async => online,
      );

  group('eskalasi ke LLM', () {
    test('ucapan yang terurai baik tidak pernah dikirim keluar', () async {
      final result = await pipeline(online: true)
          .parse('jual indomie dua bungkus lima ribu');

      expect(llm.calls, 0);
      expect(llm.seenTranscripts, isEmpty);
      expect(log.entries, isEmpty);
      expect(result.source, ParseSource.rule);
    });

    test('arah yang tidak tersebut memicu eskalasi', () async {
      final result = await pipeline(online: true).parse('teh botol 3 15rb');

      expect(llm.calls, 1);
      expect(result.source, ParseSource.hybrid);
      expect(result.direction.value, TxDirection.masuk);
    });

    test('saat luring, transkrip tidak dikirim ke mana pun', () async {
      final result = await pipeline(online: false).parse('teh botol 3 15rb');

      expect(llm.calls, 0);
      expect(llm.seenTranscripts, isEmpty);
      expect(result.source, ParseSource.rule);
      expect(result.direction.isPresent, isFalse);
    });

    test('saat fitur dimatikan, hasil aturan dipakai apa adanya', () async {
      final result = await pipeline(
        online: true,
        parser: const DisabledLlmParser(),
      ).parse('teh botol 3 15rb');

      expect(result.source, ParseSource.rule);
      expect(result.direction.isPresent, isFalse);
    });
  });

  group('gerbang sakelar', () {
    test('GatedLlmParser tidak memanggil delegasi saat sakelar mati', () async {
      final gated = GatedLlmParser(isEnabled: () async => false, delegate: llm);

      final outcome = await gated.refine(
        transcript: 'apa pun',
        ruleResult: ParseResult.empty(
          transcript: 'apa pun',
          parserVersion: 'rule-v1',
        ),
      );

      expect(outcome, isA<LlmUnavailable>());
      expect(llm.calls, 0);
    });

    test('sakelar diperiksa tiap pemanggilan, bukan sekali di awal', () async {
      var enabled = false;
      final gated = GatedLlmParser(
        isEnabled: () async => enabled,
        delegate: llm,
      );
      final empty = ParseResult.empty(
        transcript: 'x',
        parserVersion: 'rule-v1',
      );

      await gated.refine(transcript: 'x', ruleResult: empty);
      expect(llm.calls, 0);

      enabled = true;
      await gated.refine(transcript: 'x', ruleResult: empty);
      expect(llm.calls, 1);
    });
  });

  group('pencatatan kegagalan', () {
    test('dicatat walau sedang luring', () async {
      await pipeline(online: false).parse('teh botol 3 15rb');

      expect(log.entries, hasLength(1));
      expect(
        log.entries.first.reasons,
        contains(ParseFailureReason.missingDirection),
      );
    });

    test('mencatat versi parser agar bisa ditelusuri', () async {
      await pipeline(online: false).parse('teh botol 3 15rb');

      expect(log.entries.first.parserVersion, isNotEmpty);
    });
  });

  group('penggabungan hasil', () {
    test('hasil aturan yang sudah yakin tidak ditimpa LLM', () async {
      // LLM palsu selalu menjawab "masuk"; aturan membaca "beli" -> keluar.
      final result = await pipeline(online: true).parse('beli galon');

      expect(result.direction.value, TxDirection.keluar);
    });
  });
}
