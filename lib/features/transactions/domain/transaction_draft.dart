/// Calon transaksi yang masih bisa disunting.
///
/// Jalur suara maupun jalur ketik manual sama-sama bermuara ke tipe ini, dan
/// keduanya memakai layar konfirmasi yang sama. Itulah sebabnya masukan manual
/// tidak mungkin menjadi "warga kelas dua": secara harfiah layarnya sama.
library;

import '../../../core/confidence.dart';
import '../../../core/transaction_kind.dart';
import '../../voice_parser/domain/parse_result.dart';
import 'transaction_record.dart';

class DraftField<T> {
  final T? value;
  final ConfidenceBand band;

  /// Potongan transkrip asal, ditampilkan sebagai petunjuk ketika nilainya
  /// terpaksa dikosongkan karena keyakinannya rendah.
  final String? rawSpan;

  const DraftField({this.value, this.band = ConfidenceBand.good, this.rawSpan});

  const DraftField.empty()
    : value = null,
      band = ConfidenceBand.poor,
      rawSpan = null;

  /// Nilai yang diketik sendiri oleh pengguna. Begitu manusia menuliskannya,
  /// tidak ada lagi alasan menandainya meragukan.
  const DraftField.entered(T this.value)
    : band = ConfidenceBand.good,
      rawSpan = null;

  bool get isPresent => value != null;

  bool get needsAttention =>
      !isPresent || band == ConfidenceBand.poor || band == ConfidenceBand.check;

  DraftField<T> withValue(T? newValue) => DraftField<T>(
    value: newValue,
    band: ConfidenceBand.good,
    rawSpan: rawSpan,
  );

  static DraftField<T> fromParsed<T>(ParsedField<T> field) {
    final band = field.band;
    return DraftField<T>(
      // Keyakinan terlalu rendah: nilainya tidak ditampilkan sebagai fakta,
      // hanya rawSpan-nya yang disajikan sebagai petunjuk.
      value: band == ConfidenceBand.poor ? null : field.value,
      band: band,
      rawSpan: field.rawSpan,
    );
  }
}

/// Penanda "tidak diubah" untuk copyWith pada field yang boleh dikosongkan.
const Object _keep = Object();

class DraftItem {
  final DraftField<String> name;
  final DraftField<int> qty;

  /// Angka harga seperti yang diisi/diucapkan, dibaca menurut [priceMode].
  final DraftField<int> unitPrice;
  final String? unit;
  final DraftField<PriceMode> priceMode;

  const DraftItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.unit,
    this.priceMode = const DraftField<PriceMode>(value: PriceMode.perUnit),
  });

  const DraftItem.empty()
    : name = const DraftField<String>.empty(),
      qty = const DraftField<int>(value: 1),
      unitPrice = const DraftField<int>.empty(),
      unit = null,
      priceMode = const DraftField<PriceMode>(value: PriceMode.perUnit);

  /// Pilihan per-satuan/total hanya bermakna untuk lebih dari satu barang.
  bool get priceModeMatters => (qty.value ?? 0) > 1;

  bool get priceIsTotal => priceMode.value == PriceMode.total;

  /// Yang benar-benar dibayar untuk baris ini — sumber kebenaran untuk semua
  /// total dan laporan.
  int? get lineTotal {
    final q = qty.value;
    final p = unitPrice.value;
    if (q == null || p == null) return null;
    return priceIsTotal ? p : q * p;
  }

  /// Harga per satuan untuk katalog dan laporan. Bila yang disebut total,
  /// ini hasil bagi yang dibulatkan; [lineTotal] tidak ikut dibulatkan.
  int? get effectiveUnitPrice {
    final q = qty.value;
    final p = unitPrice.value;
    if (q == null || p == null || q <= 0) return null;
    return priceIsTotal ? (p / q).round() : p;
  }

  bool get isComplete =>
      (name.value?.trim().isNotEmpty ?? false) &&
      (qty.value ?? 0) > 0 &&
      unitPrice.value != null &&
      unitPrice.value! >= 0;

  bool get needsAttention =>
      name.needsAttention ||
      qty.needsAttention ||
      unitPrice.needsAttention ||
      (priceModeMatters && priceMode.needsAttention);

  DraftItem copyWith({
    DraftField<String>? name,
    DraftField<int>? qty,
    DraftField<int>? unitPrice,
    Object? unit = _keep,
    DraftField<PriceMode>? priceMode,
  }) => DraftItem(
    name: name ?? this.name,
    qty: qty ?? this.qty,
    unitPrice: unitPrice ?? this.unitPrice,
    unit: identical(unit, _keep) ? this.unit : unit as String?,
    priceMode: priceMode ?? this.priceMode,
  );
}

class TransactionDraft {
  final DraftField<TxDirection> direction;

  /// Boleh kosong: selama arah sudah dipilih, [effectiveCategory] memakai
  /// tebakan bawaan untuk arah itu, jadi pengguna tidak dipaksa memilih dua
  /// kali.
  final DraftField<TxCategory> category;
  final List<DraftItem> items;
  final DateTime occurredAt;
  final String? note;
  final TxSource source;

  /// Pelanggan (untuk penjualan) atau supplier (untuk pembelian), opsional.
  final String? contactId;

  /// Transkrip asli, disimpan hanya untuk ditampilkan saat konfirmasi.
  final String? transcript;

  const TransactionDraft({
    required this.direction,
    required this.items,
    required this.occurredAt,
    required this.source,
    this.category = const DraftField<TxCategory>.empty(),
    this.note,
    this.contactId,
    this.transcript,
  });

  factory TransactionDraft.manual({DateTime? occurredAt}) => TransactionDraft(
    direction: const DraftField<TxDirection>.empty(),
    items: const [DraftItem.empty()],
    occurredAt: occurredAt ?? DateTime.now(),
    source: TxSource.manual,
  );

  factory TransactionDraft.fromParseResult(
    ParseResult result, {
    DateTime? occurredAt,
  }) => TransactionDraft(
    direction: DraftField.fromParsed(result.direction),
    category: DraftField.fromParsed(result.category),
    items: result.items.isEmpty
        ? const [DraftItem.empty()]
        : [
            for (final item in result.items)
              DraftItem(
                name: DraftField.fromParsed(item.name),
                qty: DraftField.fromParsed(item.qty),
                unitPrice: DraftField.fromParsed(item.unitPrice),
                unit: item.unit,
                priceMode: DraftField.fromParsed(item.priceMode),
              ),
          ],
    occurredAt: occurredAt ?? DateTime.now(),
    source: TxSource.voice,
    transcript: result.transcript,
  );

  /// Draft untuk mengoreksi transaksi yang sudah tersimpan. Semua nilai
  /// dianggap sudah diperiksa manusia, jadi tidak ada yang disorot.
  factory TransactionDraft.fromRecord(TxRecord record) => TransactionDraft(
    direction: DraftField.entered(record.direction),
    category: DraftField.entered(record.category),
    items: record.items.isEmpty
        ? const [DraftItem.empty()]
        : [
            for (final item in record.items)
              // Harga total yang tidak habis dibagi ("3 porsi 25 ribu")
              // disajikan lagi sebagai total supaya angkanya tidak bergeser
              // karena pembulatan.
              if (item.lineTotal != item.qty * item.unitPrice)
                DraftItem(
                  name: DraftField.entered(item.name),
                  qty: DraftField.entered(item.qty),
                  unitPrice: DraftField.entered(item.lineTotal),
                  unit: item.unit,
                  priceMode: const DraftField.entered(PriceMode.total),
                )
              else
                DraftItem(
                  name: DraftField.entered(item.name),
                  qty: DraftField.entered(item.qty),
                  unitPrice: DraftField.entered(item.unitPrice),
                  unit: item.unit,
                ),
          ],
    occurredAt: record.occurredAt,
    note: record.note,
    source: record.source,
    contactId: record.contactId,
  );

  /// Kategori yang akan disimpan. Kategori yang tidak searah dengan arah
  /// terpilih (mis. arah diganti setelah parser menebak) diabaikan.
  TxCategory? get effectiveCategory {
    final dir = direction.value;
    if (dir == null) return null;
    final chosen = category.value;
    if (chosen != null && chosen.direction == dir) return chosen;
    return TxCategory.defaultFor(dir);
  }

  int get total {
    var sum = 0;
    for (final item in items) {
      sum += item.lineTotal ?? 0;
    }
    return sum;
  }

  /// Draft hanya boleh disimpan bila seluruh field wajib sudah terisi.
  bool get isComplete =>
      direction.isPresent &&
      items.isNotEmpty &&
      items.every((item) => item.isComplete);

  /// Field yang perlu diperiksa pengguna, dipakai layar konfirmasi untuk
  /// menentukan sorotan dan urutan fokus.
  bool get needsAttention =>
      direction.needsAttention || items.any((item) => item.needsAttention);

  TransactionDraft copyWith({
    DraftField<TxDirection>? direction,
    DraftField<TxCategory>? category,
    List<DraftItem>? items,
    DateTime? occurredAt,
    String? note,
    Object? contactId = _keep,
  }) => TransactionDraft(
    direction: direction ?? this.direction,
    category: category ?? this.category,
    items: items ?? this.items,
    occurredAt: occurredAt ?? this.occurredAt,
    note: note ?? this.note,
    contactId: identical(contactId, _keep)
        ? this.contactId
        : contactId as String?,
    source: source,
    transcript: transcript,
  );
}
