/// Detail bahan: stok sekarang, catat pemakaian/penyesuaian, dan riwayat
/// pergerakan stok.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/product_dao.dart';
import '../../../core/format.dart';
import '../catalog_providers.dart';
import 'product_form_sheet.dart';

final _productDetailProvider = FutureProvider.autoDispose
    .family<
      ({ProductWithStock item, List<StockMovementRecord> movements})?,
      String
    >((ref, id) async {
      final all = await ref.watch(productsProvider(ProductKind.bahan).future);
      final item = all.where((p) => p.product.id == id).firstOrNull;
      if (item == null) return null;
      final movements = await ref.watch(productDaoProvider).movements(id);
      return (item: item, movements: movements);
    });

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    ProductWithStock item,
    StockReason reason,
  ) async {
    final result = await showDialog<({int qty, String? note})>(
      context: context,
      builder: (_) => _StockDialog(item: item, reason: reason),
    );
    if (result == null) return;
    final delta = reason == StockReason.pemakaian
        ? -result.qty
        : result.qty - item.stock; // penyesuaian: isi = hasil hitung fisik
    if (delta == 0) return;
    final now = DateTime.now();
    await ref
        .read(productDaoProvider)
        .addMovement(
          storeId: item.product.storeId,
          productId: item.product.id,
          qtyDelta: delta,
          reason: reason,
          occurredAt: now,
          now: now,
          note: result.note,
        );
    ref.read(dataRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_productDetailProvider(productId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.item.product.name ?? 'Bahan'),
        actions: [
          if (async.value case final data?)
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showProductForm(
                context,
                kind: ProductKind.bahan,
                existing: data.item.product,
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Bahan ini sudah disembunyikan.'));
          }
          final item = data.item;
          final p = item.product;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: item.isLow
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stok sekarang', style: theme.textTheme.labelLarge),
                      Text(
                        formatQty(item.stock, p.unit),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.isLow)
                        Text(
                          'Menipis (batas ${formatQty(p.lowStockThreshold!, p.unit)}). '
                          'Saatnya belanja lagi.',
                        )
                      else if (p.lowStockThreshold == null)
                        Text(
                          'Belum ada batas minimum. Atur lewat tombol ubah '
                          'agar diingatkan saat menipis.',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (p.defaultPrice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Harga beli terakhir ${formatRupiah(p.defaultPrice!)}'
                            '${p.unit == null ? '' : '/${p.unit}'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _record(context, ref, item, StockReason.pemakaian),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Catat pemakaian'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _record(context, ref, item, StockReason.penyesuaian),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Hitung ulang'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Stok bertambah otomatis saat kamu mencatat pembelian bahan ini.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text('Riwayat stok', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (data.movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Belum ada pergerakan stok.'),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final m in data.movements)
                        ListTile(
                          dense: true,
                          leading: Icon(switch (m.reason) {
                            StockReason.pembelian => Icons.add_shopping_cart,
                            StockReason.pemakaian =>
                              Icons.soup_kitchen_outlined,
                            StockReason.penyesuaian =>
                              Icons.fact_check_outlined,
                          }),
                          title: Text(m.reason.label),
                          subtitle: Text(
                            [
                              '${formatShortDate(m.occurredAt)} ${formatTime(m.occurredAt)}',
                              if (m.note case final note? when note.isNotEmpty)
                                note,
                            ].join(' · '),
                          ),
                          trailing: Text(
                            '${m.qtyDelta > 0 ? '+' : '−'}${formatQty(m.qtyDelta.abs(), p.unit)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: m.qtyDelta > 0
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StockDialog extends StatefulWidget {
  final ProductWithStock item;
  final StockReason reason;

  const _StockDialog({required this.item, required this.reason});

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final _qty = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  bool get _isUse => widget.reason == StockReason.pemakaian;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null || qty < 0 || (_isUse && qty == 0)) {
      setState(() => _error = 'Isi angka bulat');
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop((qty: qty, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item.product.unit;
    return AlertDialog(
      title: Text(_isUse ? 'Catat pemakaian' : 'Hitung ulang stok'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isUse
                ? 'Berapa ${widget.item.product.name} yang terpakai?'
                : 'Berapa ${widget.item.product.name} yang ada sekarang? '
                      '(tercatat ${formatQty(widget.item.stock, unit)})',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Jumlah',
              suffixText: unit,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: 'Catatan (opsional)',
              hintText: _isUse ? 'Mis. masak siang' : 'Mis. ada yang busuk',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}
