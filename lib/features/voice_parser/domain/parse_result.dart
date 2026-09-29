/// Model hasil parsing ucapan menjadi calon transaksi.
///
/// Pure Dart — tidak boleh mengimpor Flutter maupun lapisan persistensi.
library;

import '../../../core/confidence.dart';
import '../../../core/transaction_kind.dart';

enum ParseSource { rule, llm, hybrid }

/// Satu field hasil parsing beserta keyakinan dan potongan teks asalnya.
class ParsedField<T> {
  final T? value;
  final Confidence confidence;

  /// Potongan transkrip yang menghasilkan nilai ini, untuk ditampilkan saat
  /// pengguna perlu menilai apakah hasilnya masuk akal.
  final String? rawSpan;

  const ParsedField({this.value, required this.confidence, this.rawSpan});

  const ParsedField.missing()
    : value = null,
      confidence = const Confidence(0),
      rawSpan = null;

  bool get isPresent => value != null;

  ConfidenceBand get band => isPresent ? confidence.band : ConfidenceBand.poor;

  ParsedField<T> copyWith({
    T? value,
    Confidence? confidence,
    String? rawSpan,
  }) => ParsedField<T>(
    value: value ?? this.value,
    confidence: confidence ?? this.confidence,
    rawSpan: rawSpan ?? this.rawSpan,
  );

  @override
  String toString() => '$value(${confidence.value?.toStringAsFixed(2) ?? '?'})';
}

class ParsedItem {
  final ParsedField<String> name;
  final ParsedField<int> qty;

  /// Angka harga seperti yang diucapkan. Apakah itu per satuan atau total
  /// ditentukan [priceMode] — nama field dipertahankan supaya korpus regresi
  /// lama tetap berlaku.
  final ParsedField<int> unitPrice;

  /// Satuan yang menempel pada kuantitas ("5 kg" → "kg"), bila ada.
  final String? unit;
  final ParsedField<PriceMode> priceMode;

  const ParsedItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.unit,
    this.priceMode = const ParsedField<PriceMode>(
      value: PriceMode.perUnit,
      confidence: Confidence(1),
    ),
  });

  int? get lineTotal {
    final q = qty.value;
    final p = unitPrice.value;
    if (q == null || p == null) return null;
    return priceMode.value == PriceMode.total ? p : q * p;
  }

  @override
  String toString() =>
      'ParsedItem(name=$name, qty=$qty, unitPrice=$unitPrice, unit=$unit, '
      'priceMode=$priceMode)';
}

class ParseResult {
  final String transcript;
  final String parserVersion;
  final ParseSource source;
  final ParsedField<TxDirection> direction;

  /// Kategori yang tersirat dari kata kerjanya ("kulakan" → pembelian,
  /// "bayar listrik" → pengeluaran). Selalu searah dengan [direction].
  final ParsedField<TxCategory> category;
  final List<ParsedItem> items;
  final ParsedField<int> totalAmount;

  /// Token yang tidak berhasil dipetakan ke field mana pun. Ini sinyal utama
  /// bahwa aturan perlu diperbaiki, dan dasar pencatatan ke parse_failures.
  final List<String> unmatchedTokens;

  const ParseResult({
    required this.transcript,
    required this.parserVersion,
    required this.source,
    required this.direction,
    required this.items,
    required this.totalAmount,
    required this.unmatchedTokens,
    this.category = const ParsedField.missing(),
  });

  factory ParseResult.empty({
    required String transcript,
    required String parserVersion,
  }) => ParseResult(
    transcript: transcript,
    parserVersion: parserVersion,
    source: ParseSource.rule,
    direction: const ParsedField.missing(),
    items: const [],
    totalAmount: const ParsedField.missing(),
    unmatchedTokens: const [],
  );

  /// Keyakinan keseluruhan = field terlemah di antara yang wajib.
  ///
  /// Sengaja memakai nilai minimum, bukan rata-rata: satu field yang meragukan
  /// sudah cukup untuk membuat seluruh transaksi perlu dicek, dan rata-rata
  /// akan menyembunyikannya di balik field lain yang kebetulan yakin.
  Confidence get overall {
    final fields = <Confidence>[
      direction.confidence,
      if (totalAmount.isPresent) totalAmount.confidence,
      for (final item in items) ...[
        item.name.confidence,
        item.qty.confidence,
        item.unitPrice.confidence,
      ],
    ];
    if (fields.isEmpty) return const Confidence(0);
    if (fields.any((c) => c.isUnknown)) return const Confidence.unknown();
    return fields.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  }

  bool get needsReview =>
      unmatchedTokens.isNotEmpty ||
      items.isEmpty ||
      overall.band != ConfidenceBand.good;

  int? get computedTotal {
    if (totalAmount.isPresent) return totalAmount.value;
    if (items.isEmpty) return null;
    var sum = 0;
    for (final item in items) {
      final line = item.lineTotal;
      if (line == null) return null;
      sum += line;
    }
    return sum;
  }

  ParseResult copyWith({
    ParseSource? source,
    ParsedField<TxDirection>? direction,
    ParsedField<TxCategory>? category,
    List<ParsedItem>? items,
    ParsedField<int>? totalAmount,
    List<String>? unmatchedTokens,
  }) => ParseResult(
    transcript: transcript,
    parserVersion: parserVersion,
    source: source ?? this.source,
    direction: direction ?? this.direction,
    category: category ?? this.category,
    items: items ?? this.items,
    totalAmount: totalAmount ?? this.totalAmount,
    unmatchedTokens: unmatchedTokens ?? this.unmatchedTokens,
  );

  @override
  String toString() =>
      'ParseResult(dir=$direction, cat=$category, items=$items, '
      'total=$totalAmount, unmatched=$unmatchedTokens, overall=$overall)';
}
