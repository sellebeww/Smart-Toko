/// Merangkai dua lapisan parser dan pencatatan kegagalannya.
///
/// Lapisan cepat berbasis aturan selalu berjalan. LLM hanya dipanggil ketika
/// aturan benar-benar mentok DAN perangkat sedang online DAN pengguna sudah
/// mengaktifkannya — penonaktifan itu diwujudkan dengan menyuntikkan
/// [DisabledLlmParser], bukan lewat pengecekan tersebar di banyak tempat.
library;

import '../../core/confidence.dart';
import '../../core/transaction_kind.dart';
import 'domain/parse_result.dart';
import 'llm/llm_parser.dart';
import 'logging/parse_failure_logger.dart';
import 'rules/rule_parser.dart';

class ParserPipeline {
  final RuleBasedParser ruleParser;
  final LlmParser llmParser;
  final ParseFailureLogger failureLogger;
  final Future<bool> Function() isOnline;

  const ParserPipeline({
    this.ruleParser = const RuleBasedParser(),
    required this.llmParser,
    required this.failureLogger,
    required this.isOnline,
  });

  Future<ParseResult> parse(
    String transcript, {
    Confidence sttConfidence = const Confidence(1),
  }) async {
    final ruleResult = ruleParser.parse(
      transcript,
      sttConfidence: sttConfidence,
    );

    final reasons = _failureReasons(ruleResult);
    if (reasons.isEmpty) return ruleResult;

    await failureLogger.record(
      ParseFailure(
        transcript: transcript,
        sttConfidence: sttConfidence.value,
        parserVersion: ruleResult.parserVersion,
        reasons: reasons,
        unmatchedTokens: ruleResult.unmatchedTokens,
        occurredAt: DateTime.now(),
      ),
    );

    if (!await isOnline()) return ruleResult;

    final outcome = await llmParser.refine(
      transcript: transcript,
      ruleResult: ruleResult,
    );

    return switch (outcome) {
      LlmParsed(:final result) => _merge(ruleResult, result),
      LlmUnavailable() => ruleResult,
    };
  }

  /// Eskalasi hanya untuk kegagalan nyata, bukan sekadar pita "perlu dicek".
  /// Hasil yang cuma agak ragu tetap layak ditampilkan apa adanya; memanggil
  /// LLM untuk itu memboroskan waktu tunggu pengguna dan mengirim transkrip
  /// keluar perangkat tanpa perlu.
  Set<ParseFailureReason> _failureReasons(ParseResult r) {
    final reasons = <ParseFailureReason>{};
    if (r.items.isEmpty) reasons.add(ParseFailureReason.noItems);
    if (r.unmatchedTokens.isNotEmpty) {
      reasons.add(ParseFailureReason.unmatchedTokens);
    }
    if (!r.direction.isPresent) {
      reasons.add(ParseFailureReason.missingDirection);
    }
    if (r.items.isNotEmpty &&
        r.direction.isPresent &&
        r.overall.band == ConfidenceBand.poor) {
      reasons.add(ParseFailureReason.lowConfidence);
    }
    return reasons;
  }

  /// Hasil aturan dipertahankan bila keyakinannya sudah baik; LLM hanya
  /// mengisi yang kosong atau meragukan. Dengan begitu perbaikan aturan tidak
  /// pernah ditimpa balik oleh tebakan model.
  ParseResult _merge(ParseResult rule, ParseResult llm) {
    final direction = rule.direction.band == ConfidenceBand.good
        ? rule.direction
        : (llm.direction.isPresent ? llm.direction : rule.direction);

    final List<ParsedItem> items;
    if (rule.items.isEmpty) {
      items = llm.items;
    } else {
      items = [
        for (var i = 0; i < rule.items.length; i++)
          _mergeItem(rule.items[i], i < llm.items.length ? llm.items[i] : null),
      ];
    }

    final usedLlm =
        !identical(direction, rule.direction) || !identical(items, rule.items);

    // Kategori dari aturan hanya berlaku bila arahnya masih sama; kalau arah
    // diambil dari LLM, kategorinya dikosongkan dan layar konfirmasi memakai
    // tebakan bawaan untuk arah itu.
    final ruleCategory = rule.category.value;
    final category =
        ruleCategory != null && ruleCategory.direction == direction.value
        ? rule.category
        : const ParsedField<TxCategory>.missing();

    return rule.copyWith(
      source: usedLlm ? ParseSource.hybrid : ParseSource.rule,
      direction: direction,
      category: category,
      items: items,
      unmatchedTokens: usedLlm ? const [] : rule.unmatchedTokens,
    );
  }

  ParsedItem _mergeItem(ParsedItem rule, ParsedItem? llm) {
    if (llm == null) return rule;
    return ParsedItem(
      name: _preferRule(rule.name, llm.name),
      qty: _preferRule(rule.qty, llm.qty),
      unitPrice: _preferRule(rule.unitPrice, llm.unitPrice),
      unit: rule.unit ?? llm.unit,
      priceMode: rule.priceMode,
    );
  }

  ParsedField<T> _preferRule<T>(ParsedField<T> rule, ParsedField<T> llm) {
    if (rule.isPresent && rule.band == ConfidenceBand.good) return rule;
    if (llm.isPresent) return llm;
    return rule;
  }
}
