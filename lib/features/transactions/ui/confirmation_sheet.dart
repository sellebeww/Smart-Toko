/// Layar konfirmasi — satu-satunya jalan menuju penyimpanan.
///
/// Dipakai OLEH KEDUA jalur masukan: hasil suara dan ketik manual. Kesamaan ini
/// disengaja. Kalau jalur manual punya layarnya sendiri, cepat atau lambat ia
/// akan tertinggal dan terasa seperti fitur darurat; dengan berbagi layar yang
/// sama, keduanya selalu sama nyamannya.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/confidence.dart';
import '../../../core/db/dao/contact_dao.dart';
import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../domain/confirmed_draft.dart';
import '../domain/transaction_draft.dart';

/// Kontak yang dipilih lewat [ConfirmationSheet.pickContact].
typedef PickedContact = ({String id, String name});

class ConfirmationSheet extends StatefulWidget {
  final TransactionDraft draft;
  final Future<void> Function(ConfirmedDraft confirmed) onConfirm;

  /// Membuka pemilih pelanggan/supplier. Disuntikkan dari luar supaya layar
  /// ini tetap widget murni tanpa akses basis data; bila null, baris kontak
  /// tidak ditampilkan.
  final Future<PickedContact?> Function(ContactKind kind)? pickContact;

  /// Nama kontak yang sudah terpasang di [draft] (dipakai saat koreksi).
  final String? initialContactName;
  final String title;

  const ConfirmationSheet({
    super.key,
    required this.draft,
    required this.onConfirm,
    this.pickContact,
    this.initialContactName,
    this.title = 'Periksa dulu sebelum disimpan',
  });

  @override
  State<ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<ConfirmationSheet> {
  late TransactionDraft _draft;
  final Set<String> _editedFields = {};
  final List<_ItemControllers> _controllers = [];
  bool _saving = false;
  String? _saveError;
  String? _contactName;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _contactName = widget.initialContactName;
    _rebuildControllers();
  }

  void _rebuildControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers
      ..clear()
      ..addAll([
        for (final item in _draft.items)
          _ItemControllers(
            name: TextEditingController(text: item.name.value ?? ''),
            qty: TextEditingController(text: item.qty.value?.toString() ?? ''),
            unit: TextEditingController(text: item.unit ?? ''),
            price: TextEditingController(
              text: item.unitPrice.value == null
                  ? ''
                  : formatNumber(item.unitPrice.value!),
            ),
          ),
      ]);
  }

  void _setCategory(TxCategory category) {
    setState(() {
      _editedFields.add('category');
      _draft = _draft.copyWith(
        category: DraftField<TxCategory>.entered(category),
      );
    });
  }

  /// Pelanggan hanya relevan untuk penjualan, supplier untuk pembelian bahan.
  ContactKind? get _contactKind => switch (_draft.effectiveCategory) {
    TxCategory.penjualan => ContactKind.pelanggan,
    TxCategory.pembelian => ContactKind.supplier,
    _ => null,
  };

  Future<void> _pickContact(ContactKind kind) async {
    final picked = await widget.pickContact!(kind);
    if (picked == null || !mounted) return;
    setState(() {
      _editedFields.add('contact');
      _contactName = picked.name;
      _draft = _draft.copyWith(contactId: picked.id);
    });
  }

  void _setOnCredit(bool value) {
    setState(() {
      _editedFields.add('credit');
      _draft = _draft.copyWith(onCredit: value);
    });
  }

  void _clearContact() {
    setState(() {
      _editedFields.add('contact');
      _contactName = null;
      _draft = _draft.copyWith(contactId: null);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _setDirection(TxDirection direction) {
    setState(() {
      _editedFields.add('direction');
      _draft = _draft.copyWith(
        direction: DraftField<TxDirection>.entered(direction),
      );
    });
  }

  void _updateItem(int index, DraftItem Function(DraftItem item) update) {
    setState(() {
      final items = [..._draft.items];
      items[index] = update(items[index]);
      _draft = _draft.copyWith(items: items);
    });
  }

  void _addItem() {
    setState(() {
      _draft = _draft.copyWith(
        items: [..._draft.items, const DraftItem.empty()],
      );
      _controllers.add(
        _ItemControllers(
          name: TextEditingController(),
          qty: TextEditingController(text: '1'),
          unit: TextEditingController(),
          price: TextEditingController(),
        ),
      );
    });
  }

  void _removeItem(int index) {
    if (_draft.items.length == 1) return;
    setState(() {
      final items = [..._draft.items]..removeAt(index);
      _draft = _draft.copyWith(items: items);
      _controllers.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // Kontak yang tidak cocok dengan kategori akhir (mis. pelanggan dipilih,
    // lalu kategori diganti ke pengeluaran) tidak ikut tersimpan.
    final draft = _contactKind == null && _draft.contactId != null
        ? _draft.copyWith(contactId: null)
        : _draft;
    final confirmed = confirmDraftByUser(
      draft: draft,
      editedFields: _editedFields,
    );
    if (confirmed == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onConfirm(confirmed);
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError =
              'Transaksi belum tersimpan. Coba lagi; isianmu tetap ada.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _draft.isComplete && !_saving;
    // Pada masukan manual tidak ada audio sama sekali, jadi kalimat bantuan
    // tidak boleh menyalahkan pendengaran.
    final fromVoice = widget.draft.source == TxSource.voice;

    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Batal',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      if (_draft.transcript != null) ...[
                        _TranscriptChip(
                          transcript: _draft.transcript!,
                          fromVoice: fromVoice,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_draft.needsAttention &&
                          _draft.transcript != null) ...[
                        _AttentionBanner(fromVoice: fromVoice),
                        const SizedBox(height: 16),
                      ],
                      _DirectionSelector(
                        field: _draft.direction,
                        fromVoice: fromVoice,
                        onChanged: _setDirection,
                      ),
                      if (_draft.effectiveCategory case final category?) ...[
                        const SizedBox(height: 12),
                        _CategorySelector(
                          selected: category,
                          onChanged: _setCategory,
                        ),
                      ],
                      if (widget.pickContact != null)
                        if (_contactKind case final kind?) ...[
                          const SizedBox(height: 8),
                          _ContactRow(
                            kind: kind,
                            name: _contactName,
                            required: _draft.isCredit,
                            onPick: () => _pickContact(kind),
                            onClear: _clearContact,
                          ),
                          _CreditToggle(
                            kind: kind,
                            value: _draft.onCredit,
                            missingContact:
                                _draft.isCredit && _draft.contactId == null,
                            onChanged: _setOnCredit,
                          ),
                        ],
                      const SizedBox(height: 20),
                      for (var i = 0; i < _draft.items.length; i++) ...[
                        _ItemEditor(
                          index: i,
                          item: _draft.items[i],
                          controllers: _controllers[i],
                          fromVoice: fromVoice,
                          canRemove: _draft.items.length > 1,
                          onRemove: () => _removeItem(i),
                          onUnitChanged: (value) {
                            _editedFields.add('item$i.unit');
                            _updateItem(
                              i,
                              (item) => item.copyWith(
                                unit: value.trim().isEmpty
                                    ? null
                                    : value.trim().toLowerCase(),
                              ),
                            );
                          },
                          onPriceModeChanged: (mode) {
                            _editedFields.add('item$i.priceMode');
                            _updateItem(
                              i,
                              (item) => item.copyWith(
                                priceMode: DraftField<PriceMode>.entered(mode),
                              ),
                            );
                          },
                          onNameChanged: (value) {
                            _editedFields.add('item$i.name');
                            _updateItem(
                              i,
                              (item) => item.copyWith(
                                name: item.name.withValue(
                                  value.trim().isEmpty ? null : value.trim(),
                                ),
                              ),
                            );
                          },
                          onQtyChanged: (value) {
                            _editedFields.add('item$i.qty');
                            _updateItem(
                              i,
                              (item) => item.copyWith(
                                qty: item.qty.withValue(int.tryParse(value)),
                              ),
                            );
                          },
                          onPriceChanged: (value) {
                            _editedFields.add('item$i.price');
                            _updateItem(
                              i,
                              (item) => item.copyWith(
                                unitPrice: item.unitPrice.withValue(
                                  parseRupiahInput(value),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah barang'),
                        ),
                      ),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: theme.textTheme.titleMedium),
                          Text(
                            formatRupiah(_draft.total),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _saveError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: canSave ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _draft.isComplete
                              ? 'Simpan'
                              : 'Lengkapi dulu yang disorot',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemControllers {
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController unit;
  final TextEditingController price;

  _ItemControllers({
    required this.name,
    required this.qty,
    required this.unit,
    required this.price,
  });

  void dispose() {
    name.dispose();
    qty.dispose();
    unit.dispose();
    price.dispose();
  }
}

/// Kategori sudah terisi tebakan begitu arah dipilih, jadi ini hanya perlu
/// disentuh bila tebakannya salah — tidak menambah langkah wajib.
class _CategorySelector extends StatelessWidget {
  final TxCategory selected;
  final ValueChanged<TxCategory> onChanged;

  const _CategorySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final category in TxCategory.forDirection(selected.direction))
          ChoiceChip(
            label: Text(category.label),
            selected: category == selected,
            onSelected: (_) => onChanged(category),
          ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ContactKind kind;
  final String? name;
  final bool required;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ContactRow({
    required this.kind,
    required this.name,
    required this.required,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final picked = name;
    if (picked == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPick,
          icon: Icon(
            kind == ContactKind.pelanggan
                ? Icons.person_add_alt
                : Icons.local_shipping_outlined,
          ),
          label: Text(
            required
                ? 'Pilih ${kind.label.toLowerCase()}'
                : '${kind.label} (opsional)',
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: InputChip(
        avatar: Icon(
          kind == ContactKind.pelanggan
              ? Icons.person_outline
              : Icons.local_shipping_outlined,
          size: 18,
        ),
        label: Text('${kind.label}: $picked'),
        onPressed: onPick,
        onDeleted: onClear,
        deleteButtonTooltipMessage: 'Lepas ${kind.label.toLowerCase()}',
      ),
    );
  }
}

/// Penanda transaksi belum dibayar. Bila menyala, nama pelanggan/supplier
/// wajib dipilih supaya sisanya bisa ditagih.
class _CreditToggle extends StatelessWidget {
  final ContactKind kind;
  final bool value;
  final bool missingContact;
  final ValueChanged<bool> onChanged;

  const _CreditToggle({
    required this.kind,
    required this.value,
    required this.missingContact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(
        kind == ContactKind.pelanggan
            ? 'Belum dibayar (kasbon pelanggan)'
            : 'Belum dibayar (utang ke supplier)',
      ),
      subtitle: Text(
        missingContact
            ? 'Pilih ${kind.label.toLowerCase()} dulu supaya bisa ditagih.'
            : 'Bisa dicicil dan dilunasi nanti dari detail transaksi.',
        style: missingContact
            ? TextStyle(color: theme.colorScheme.error, fontSize: 12)
            : const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _TranscriptChip extends StatelessWidget {
  final String transcript;

  final bool fromVoice;
  const _TranscriptChip({required this.transcript, required this.fromVoice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fromVoice ? Icons.hearing : Icons.edit_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '"$transcript"',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  final bool fromVoice;
  const _AttentionBanner({required this.fromVoice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fromVoice
                  ? 'Ada yang kurang jelas terdengar. Bagian bertanda perlu dicek.'
                  : 'Ada bagian teks yang perlu diperiksa. Cek bagian bertanda sebelum menyimpan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arah transaksi tidak punya nilai awal bila parser tidak yakin.
///
/// Memilihkan "masuk" secara diam-diam berisiko mencatat pengeluaran sebagai
/// pemasukan, dan pengguna yang terburu-buru tidak akan menyadarinya.
class _DirectionSelector extends StatelessWidget {
  final DraftField<TxDirection> field;
  final bool fromVoice;
  final ValueChanged<TxDirection> onChanged;

  const _DirectionSelector({
    required this.field,
    required this.fromVoice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = !field.isPresent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Jenis transaksi', style: theme.textTheme.labelLarge),
            if (missing) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<TxDirection>(
          segments: const [
            ButtonSegment(
              value: TxDirection.masuk,
              icon: Icon(Icons.south_west),
              label: Text('Masuk'),
            ),
            ButtonSegment(
              value: TxDirection.keluar,
              icon: Icon(Icons.north_east),
              label: Text('Keluar'),
            ),
          ],
          selected: field.value == null ? const {} : {field.value!},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onChanged(selection.first);
          },
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              fromVoice
                  ? 'Tidak terdengar jelas — pilih sendiri'
                  : 'Pilih dulu masuk atau keluar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _ItemEditor extends StatelessWidget {
  final int index;
  final DraftItem item;
  final _ItemControllers controllers;
  final bool fromVoice;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onQtyChanged;
  final ValueChanged<String> onUnitChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<PriceMode> onPriceModeChanged;

  const _ItemEditor({
    required this.index,
    required this.item,
    required this.controllers,
    required this.fromVoice,
    required this.canRemove,
    required this.onRemove,
    required this.onNameChanged,
    required this.onQtyChanged,
    required this.onUnitChanged,
    required this.onPriceChanged,
    required this.onPriceModeChanged,
  });

  String _summary() {
    final total = item.lineTotal;
    if (total == null) return '';
    if (!item.priceModeMatters) return 'Subtotal ${formatRupiah(total)}';
    final perUnit = item.effectiveUnitPrice!;
    final unit = item.unit ?? 'satuan';
    return item.priceIsTotal
        ? 'Total ${formatRupiah(total)} · ≈ ${formatRupiah(perUnit)}/$unit'
        : '${formatRupiah(perUnit)}/$unit · subtotal ${formatRupiah(total)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ConfidenceField(
                    controller: controllers.name,
                    field: item.name,
                    fromVoice: fromVoice,
                    label: 'Nama barang',
                    onChanged: onNameChanged,
                    autofocus: !item.name.isPresent && index == 0,
                  ),
                ),
                if (canRemove)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Hapus barang',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: _ConfidenceField(
                    controller: controllers.qty,
                    field: item.qty,
                    fromVoice: fromVoice,
                    label: 'Jumlah',
                    errorText: item.qty.value != null && item.qty.value! <= 0
                        ? 'Minimal 1'
                        : null,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: onQtyChanged,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: controllers.unit,
                    onChanged: onUnitChanged,
                    decoration: const InputDecoration(
                      labelText: 'Satuan',
                      hintText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ConfidenceField(
                    controller: controllers.price,
                    field: item.unitPrice,
                    fromVoice: fromVoice,
                    label: item.priceModeMatters && item.priceIsTotal
                        ? 'Harga total'
                        : 'Harga satuan',
                    prefixText: 'Rp ',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: onPriceChanged,
                  ),
                ),
              ],
            ),
            if (item.priceModeMatters) ...[
              const SizedBox(height: 10),
              _PriceModeToggle(
                field: item.priceMode,
                onChanged: onPriceModeChanged,
              ),
            ],
            if (item.lineTotal != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(_summary(), style: theme.textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Beli ayam 5 kg 200 ribu": 200 ribu itu per kg atau semuanya? Pilihan ini
/// ditampilkan terang-terangan karena salah baca di sini melipatgandakan
/// angka transaksi — dan tebakan parser disorot sampai dikonfirmasi.
class _PriceModeToggle extends StatelessWidget {
  final DraftField<PriceMode> field;
  final ValueChanged<PriceMode> onChanged;

  const _PriceModeToggle({required this.field, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uncertain = field.band != ConfidenceBand.good;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          uncertain ? 'Cek: harga di atas untuk…' : 'Harga di atas untuk',
          style: theme.textTheme.labelMedium?.copyWith(
            color: uncertain ? theme.colorScheme.tertiary : null,
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<PriceMode>(
          segments: const [
            ButtonSegment(value: PriceMode.perUnit, label: Text('Per satuan')),
            ButtonSegment(value: PriceMode.total, label: Text('Semuanya')),
          ],
          selected: {field.value ?? PriceMode.perUnit},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

/// Field teks yang menampilkan tingkat keyakinan hasil pengenalan.
class _ConfidenceField extends StatelessWidget {
  final TextEditingController controller;
  final DraftField<Object?> field;
  final String label;
  final String? errorText;
  final bool fromVoice;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  const _ConfidenceField({
    required this.controller,
    required this.field,
    required this.label,
    required this.fromVoice,
    required this.onChanged,
    this.prefixText,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (
      Color? borderColor,
      String? helper,
      IconData? icon,
    ) = switch (field.band) {
      ConfidenceBand.good => (null, null, null),
      ConfidenceBand.check => (
        scheme.tertiary,
        field.rawSpan == null
            ? 'Cek lagi'
            : fromVoice
            ? 'Terdengar: "${field.rawSpan}"'
            : 'Dari teks: "${field.rawSpan}"',
        Icons.help_outline,
      ),
      ConfidenceBand.poor => (
        scheme.error,
        switch ((fromVoice, field.rawSpan)) {
          (true, final String span) => 'Kurang jelas, terdengar: "$span"',
          (false, final String span) => 'Periksa teks: "$span"',
          (true, _) => 'Tidak terdengar jelas — isi sendiri',
          (false, _) => 'Belum diisi',
        },
        Icons.error_outline,
      ),
    };

    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixText: prefixText,
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: borderColor == null
            ? null
            : theme.textTheme.bodySmall?.copyWith(color: borderColor),
        suffixIcon: icon == null
            ? null
            : Icon(icon, color: borderColor, size: 20),
        border: const OutlineInputBorder(),
        enabledBorder: borderColor == null
            ? null
            : OutlineInputBorder(
                borderSide: BorderSide(color: borderColor, width: 1.5),
              ),
      ),
    );
  }
}
