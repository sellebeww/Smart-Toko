/// Parser berbasis aturan: cepat, deterministik, dan berjalan offline.
///
/// Ini lapisan pertama. Bila keyakinannya rendah atau ada token tersisa,
/// [ParserPipeline] yang memutuskan apakah perlu meminta bantuan LLM.
library;

import '../../../core/confidence.dart';
import '../../../core/transaction_kind.dart';
import '../domain/parse_result.dart';
import 'indonesian_number.dart';
import 'keywords.dart';
import 'tokenizer.dart';

/// v2: kategori transaksi, satuan, dan pembacaan harga per-satuan vs total.
const String ruleParserVersion = 'rule-v2';

const Set<String> _scaleSpanWords = {
  'ribu',
  'seribu',
  'juta',
  'sejuta',
  'miliar',
  'milyar',
};

enum _NumberRole { qty, price }

class _ClassifiedNumber {
  final NumberMatch match;
  final _NumberRole role;
  final double strength;

  /// Indeks token satuan yang menempel ("tiga kilo"), bila ada.
  final int? unitTokenIndex;

  const _ClassifiedNumber({
    required this.match,
    required this.role,
    required this.strength,
    this.unitTokenIndex,
  });
}

class RuleBasedParser {
  const RuleBasedParser();

  ParseResult parse(
    String transcript, {
    Confidence sttConfidence = const Confidence(1),
  }) {
    final tokens = tokenize(transcript);
    if (tokens.isEmpty) {
      return ParseResult.empty(
        transcript: transcript,
        parserVersion: ruleParserVersion,
      );
    }

    final consumed = List<bool>.filled(tokens.length, false);

    final direction = _findDirection(tokens, consumed, sttConfidence);
    final segments = _splitSegments(tokens, consumed);

    final items = <ParsedItem>[];
    final unmatched = <String>[];
    final extraPrices = <_ClassifiedNumber>[];

    for (final segment in segments) {
      final parsed = _parseSegment(
        tokens,
        segment,
        consumed,
        sttConfidence,
        unmatched,
        extraPrices,
      );
      if (parsed != null) items.add(parsed);
    }

    // Harga kedua yang tersisa diperlakukan sebagai total yang diucapkan
    // terpisah ("... lima ribu, total sepuluh ribu"). Keyakinannya rendah
    // karena tebakan ini mudah salah.
    ParsedField<int> totalAmount = const ParsedField.missing();
    if (extraPrices.isNotEmpty) {
      final extra = extraPrices.first;
      totalAmount = ParsedField<int>(
        value: extra.match.asRupiah,
        confidence: sttConfidence.combine(const Confidence(0.60)),
        rawSpan: _span(tokens, extra.match.startToken, extra.match.endToken),
      );
    }

    return ParseResult(
      transcript: transcript,
      parserVersion: ruleParserVersion,
      source: ParseSource.rule,
      direction: direction,
      category: _findCategory(tokens, direction, sttConfidence),
      items: items,
      totalAmount: totalAmount,
      unmatchedTokens: unmatched,
    );
  }

  /// Kategori diturunkan dari kata kerja arah, lalu dikoreksi oleh bendanya:
  /// "beli gas" tetap keluar, tapi pengeluaran operasional, bukan belanja
  /// bahan — jadi tidak menambah stok.
  ParsedField<TxCategory> _findCategory(
    List<String> tokens,
    ParsedField<TxDirection> direction,
    Confidence stt,
  ) {
    final dir = direction.value;
    if (dir == null) return const ParsedField.missing();

    var category =
        categoryWords[direction.rawSpan] ?? TxCategory.defaultFor(dir);
    if (dir == TxDirection.keluar &&
        tokens.any(operationalExpenseWords.contains)) {
      category = TxCategory.pengeluaran;
    }
    return ParsedField<TxCategory>(
      value: category,
      confidence: stt.combine(const Confidence(0.90)),
      rawSpan: direction.rawSpan,
    );
  }

  /// Arah transaksi sengaja TIDAK diberi nilai default.
  ///
  /// Menebak "masuk" karena penjualan lebih sering terjadi berisiko mencatat
  /// pengeluaran sebagai pemasukan tanpa pengguna sadar. Lebih baik kosong dan
  /// ditanyakan di layar konfirmasi.
  ParsedField<TxDirection> _findDirection(
    List<String> tokens,
    List<bool> consumed,
    Confidence stt,
  ) {
    for (var i = 0; i < tokens.length; i++) {
      final dir = directionWords[tokens[i]];
      if (dir != null) {
        consumed[i] = true;
        return ParsedField<TxDirection>(
          value: dir,
          confidence: stt.combine(const Confidence(0.95)),
          rawSpan: tokens[i],
        );
      }
    }
    return const ParsedField.missing();
  }

  List<List<int>> _splitSegments(List<String> tokens, List<bool> consumed) {
    final segments = <List<int>>[];
    var current = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (consumed[i]) continue;
      if (tokens[i] == separatorToken || isSeparator(tokens[i])) {
        consumed[i] = true;
        if (current.isNotEmpty) segments.add(current);
        current = <int>[];
        continue;
      }
      current.add(i);
    }
    if (current.isNotEmpty) segments.add(current);
    return segments;
  }

  ParsedItem? _parseSegment(
    List<String> tokens,
    List<int> segment,
    List<bool> consumed,
    Confidence stt,
    List<String> unmatched,
    List<_ClassifiedNumber> extraPrices,
  ) {
    final numbers = _classifyNumbers(tokens, segment);

    for (final n in numbers) {
      for (var i = n.match.startToken; i < n.match.endToken; i++) {
        consumed[i] = true;
      }
      final unitIndex = n.unitTokenIndex;
      if (unitIndex != null) consumed[unitIndex] = true;
    }

    for (var i = 0; i < tokens.length; i++) {
      if (!consumed[i] &&
          (isFiller(tokens[i]) ||
              priceMarkers.contains(tokens[i]) ||
              qtyMarkers.contains(tokens[i]) ||
              perUnitPriceMarkers.contains(tokens[i]) ||
              totalPriceMarkers.contains(tokens[i]))) {
        if (segment.contains(i)) consumed[i] = true;
      }
    }

    // "40 ribu per kilo": satuan sesudah penanda "per" bukan bagian nama.
    for (final i in segment) {
      final next = i + 1;
      if (perUnitPriceMarkers.contains(tokens[i]) &&
          segment.contains(next) &&
          isUnitWord(tokens[next])) {
        consumed[next] = true;
      }
    }

    final qtyNumbers = numbers.where((n) => n.role == _NumberRole.qty).toList();
    final priceNumbers = numbers
        .where((n) => n.role == _NumberRole.price)
        .toList();

    if (priceNumbers.length > 1) {
      extraPrices.addAll(priceNumbers.skip(1));
    }

    final runs = _contentRuns(tokens, segment, consumed);
    if (runs.isEmpty && numbers.isEmpty) return null;

    final nameRun = _pickNameRun(runs);
    for (final run in runs) {
      if (run == nameRun) continue;
      unmatched.addAll(run.map((i) => tokens[i]));
    }

    final name = nameRun == null
        ? const ParsedField<String>.missing()
        : ParsedField<String>(
            value: nameRun.map((i) => tokens[i]).join(' '),
            // Nama yang terpecah jadi beberapa potongan menandakan parser
            // kehilangan struktur kalimat, jadi keyakinannya diturunkan.
            confidence: stt.combine(Confidence(runs.length > 1 ? 0.65 : 0.90)),
            rawSpan: nameRun.map((i) => tokens[i]).join(' '),
          );

    final ParsedField<int> qty;
    if (qtyNumbers.isNotEmpty) {
      final q = qtyNumbers.first;
      qty = ParsedField<int>(
        value: q.match.asRupiah,
        confidence: stt.combine(Confidence(q.strength)),
        rawSpan: _span(tokens, q.match.startToken, q.match.endToken),
      );
    } else {
      // Tanpa kuantitas yang disebut, satu unit adalah asumsi yang wajar
      // ("jual es teh dua ribu"), tapi tetap ditandai agar bisa dikoreksi.
      qty = ParsedField<int>(
        value: 1,
        confidence: stt.combine(const Confidence(0.85)),
      );
    }

    final ParsedField<int> unitPrice;
    if (priceNumbers.isNotEmpty) {
      final p = priceNumbers.first;
      unitPrice = ParsedField<int>(
        value: p.match.asRupiah,
        confidence: stt.combine(Confidence(p.strength)),
        rawSpan: _span(tokens, p.match.startToken, p.match.endToken),
      );
    } else {
      unitPrice = const ParsedField<int>.missing();
    }

    if (!name.isPresent && !unitPrice.isPresent) return null;

    final unitIndex = qtyNumbers.isEmpty
        ? null
        : qtyNumbers.first.unitTokenIndex;
    final unit = unitIndex == null ? null : normalizeUnit(tokens[unitIndex]);

    return ParsedItem(
      name: name,
      qty: qty,
      unitPrice: unitPrice,
      unit: unit,
      priceMode: _priceMode(tokens, segment, qty.value, unit, stt),
    );
  }

  /// Membaca harga sebagai per satuan atau total.
  ///
  /// Penanda eksplisit ("per kilo", "semuanya") menang. Tanpa penanda, satuan
  /// timbang/takar dibaca total ("beli ayam 5 kg 200 ribu" = 200 ribu, bukan
  /// 1 juta) dan sisanya per satuan ("gorengan 10 biji seribu") — tapi
  /// keduanya tebakan, jadi diberi keyakinan "cek lagi" agar disorot di layar
  /// konfirmasi.
  ParsedField<PriceMode> _priceMode(
    List<String> tokens,
    List<int> segment,
    int? qty,
    String? unit,
    Confidence stt,
  ) {
    if (qty == null || qty <= 1) {
      // Untuk satu barang, per satuan dan total sama saja.
      return const ParsedField<PriceMode>(
        value: PriceMode.perUnit,
        confidence: Confidence(1),
      );
    }
    final words = [for (final i in segment) tokens[i]];
    if (words.any(perUnitPriceMarkers.contains)) {
      return ParsedField<PriceMode>(
        value: PriceMode.perUnit,
        confidence: stt.combine(const Confidence(0.95)),
      );
    }
    if (words.any(totalPriceMarkers.contains)) {
      return ParsedField<PriceMode>(
        value: PriceMode.total,
        confidence: stt.combine(const Confidence(0.95)),
      );
    }
    if (unit != null && bulkUnits.contains(unit)) {
      return ParsedField<PriceMode>(
        value: PriceMode.total,
        confidence: stt.combine(const Confidence(0.70)),
      );
    }
    return ParsedField<PriceMode>(
      value: PriceMode.perUnit,
      // Sama dengan kebiasaan lama parser ini, jadi tidak ikut disorot; yang
      // disorot hanya pembacaan "total" yang benar-benar baru.
      confidence: stt.combine(const Confidence(0.85)),
    );
  }

  List<_ClassifiedNumber> _classifyNumbers(
    List<String> tokens,
    List<int> segment,
  ) {
    if (segment.isEmpty) return const [];
    final result = <_ClassifiedNumber>[];
    final segmentSet = segment.toSet();

    var i = segment.first;
    final end = segment.last + 1;
    while (i < end) {
      if (!segmentSet.contains(i)) {
        i++;
        continue;
      }
      final match = readNumberAt(tokens, i);
      if (match == null || match.endToken <= match.startToken) {
        i++;
        continue;
      }

      final spanTokens = tokens.sublist(match.startToken, match.endToken);
      final hasScale = spanTokens.any(_scaleSpanWords.contains);
      final nextIndex = match.endToken;
      final nextToken = nextIndex < tokens.length ? tokens[nextIndex] : null;
      final prevToken = match.startToken > 0
          ? tokens[match.startToken - 1]
          : null;

      _NumberRole role;
      double strength;
      int? unitIndex;

      if (prevToken != null && priceMarkers.contains(prevToken)) {
        role = _NumberRole.price;
        strength = 0.95;
      } else if (prevToken != null && qtyMarkers.contains(prevToken)) {
        role = _NumberRole.qty;
        strength = 0.95;
      } else if (nextToken != null && isUnitWord(nextToken)) {
        role = _NumberRole.qty;
        strength = 0.95;
        unitIndex = nextIndex;
      } else if (hasScale) {
        role = _NumberRole.price;
        strength = 0.95;
      } else if (match.value >= 1000) {
        role = _NumberRole.price;
        strength = 0.90;
      } else if (match.value <= 100 &&
          match.value == match.value.roundToDouble()) {
        // Angka kecil tanpa penanda apa pun: kemungkinan besar kuantitas,
        // tapi inilah tebakan paling rapuh di parser ini.
        role = _NumberRole.qty;
        strength = 0.65;
      } else {
        role = _NumberRole.price;
        strength = 0.70;
      }

      result.add(
        _ClassifiedNumber(
          match: match,
          role: role,
          strength: strength,
          unitTokenIndex: unitIndex,
        ),
      );
      i = match.endToken;
    }
    return result;
  }

  List<List<int>> _contentRuns(
    List<String> tokens,
    List<int> segment,
    List<bool> consumed,
  ) {
    final runs = <List<int>>[];
    var current = <int>[];
    for (final i in segment) {
      if (consumed[i]) {
        if (current.isNotEmpty) {
          runs.add(current);
          current = <int>[];
        }
        continue;
      }
      current.add(i);
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  /// Run terpanjang dianggap nama barang; bila seri, yang paling awal menang.
  List<int>? _pickNameRun(List<List<int>> runs) {
    if (runs.isEmpty) return null;
    var best = runs.first;
    for (final run in runs.skip(1)) {
      if (run.length > best.length) best = run;
    }
    return best;
  }

  String _span(List<String> tokens, int start, int end) =>
      tokens.sublist(start, end).join(' ');
}
