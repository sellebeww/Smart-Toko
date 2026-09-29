/// Form tambah/ubah menu atau bahan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/product_dao.dart';
import '../../../core/format.dart';

Future<void> showProductForm(
  BuildContext context, {
  required ProductKind kind,
  ProductRecord? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProductForm(kind: kind, existing: existing),
  );
}

class _ProductForm extends ConsumerStatefulWidget {
  final ProductKind kind;
  final ProductRecord? existing;

  const _ProductForm({required this.kind, this.existing});

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _unit = TextEditingController(text: widget.existing?.unit);
  late final _price = TextEditingController(
    text: widget.existing?.defaultPrice == null
        ? ''
        : formatNumber(widget.existing!.defaultPrice!),
  );
  late final _threshold = TextEditingController(
    text: widget.existing?.lowStockThreshold?.toString() ?? '',
  );
  bool _saving = false;
  String? _error;

  bool get _isBahan => widget.kind == ProductKind.bahan;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final storeId = ref.read(activeStoreIdProvider);
    if (storeId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final dao = ref.read(productDaoProvider);
    final navigator = Navigator.of(context);
    final now = DateTime.now();
    final price = parseRupiahInput(_price.text);
    final threshold = int.tryParse(_threshold.text.trim());
    try {
      var product = widget.existing;
      if (product == null) {
        final existingNames = await dao.list(
          storeId: storeId,
          kind: widget.kind,
          includeArchived: true,
        );
        final key = ProductDao.nameKey(_name.text);
        if (existingNames.any(
          (p) => ProductDao.nameKey(p.name) == key && !p.archived,
        )) {
          throw DuplicateProductNameException(_name.text.trim());
        }
        product = await dao.findOrCreate(
          storeId: storeId,
          kind: widget.kind,
          name: _name.text,
          unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
          price: price,
          now: now,
        );
      }
      await dao.update(
        product,
        name: _name.text,
        unit: _unit.text,
        defaultPrice: price,
        lowStockThreshold: _isBahan ? threshold : null,
        now: now,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      navigator.pop();
    } on DuplicateProductNameException catch (e) {
      setState(() {
        _saving = false;
        _error =
            '"${e.name}" sudah ada di daftar ${widget.kind.label.toLowerCase()}.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Belum tersimpan. Coba lagi.';
        });
      }
    }
  }

  Future<void> _archive() async {
    final product = widget.existing!;
    await ref.read(productDaoProvider).setArchived(product.id, archived: true);
    ref.read(dataRevisionProvider.notifier).bump();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} disembunyikan'),
        action: SnackBarAction(
          label: 'Batal',
          onPressed: () async {
            await ref
                .read(productDaoProvider)
                .setArchived(product.id, archived: false);
            ref.read(dataRevisionProvider.notifier).bump();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final kindLabel = widget.kind.label.toLowerCase();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${isEdit ? 'Ubah' : 'Tambah'} $kindLabel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nama $kindLabel',
                hintText: _isBahan ? 'Mis. ayam' : 'Mis. nasi ayam',
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _unit,
                    decoration: InputDecoration(
                      labelText: 'Satuan',
                      hintText: _isBahan ? 'kg' : 'porsi',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _isBahan ? 'Harga beli' : 'Harga jual',
                      prefixText: 'Rp',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (_isBahan) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _threshold,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ingatkan bila stok ≤ (opsional)',
                  hintText: 'Mis. 2',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return int.tryParse(v.trim()) == null
                      ? 'Isi angka bulat'
                      : null;
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Simpan'),
            ),
            if (isEdit)
              TextButton(
                onPressed: _saving ? null : _archive,
                child: Text('Sembunyikan $kindLabel ini'),
              ),
          ],
        ),
      ),
    );
  }
}
