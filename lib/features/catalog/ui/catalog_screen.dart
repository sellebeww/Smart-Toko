/// Katalog Menu dan Bahan beserta stok bahan.
///
/// Katalog tumbuh sendiri dari transaksi: menjual "nasi ayam" menambah menu,
/// membeli "ayam 5 kg" menambah bahan sekaligus stoknya. Layar ini untuk
/// merapikan (ganti nama, harga, batas stok) dan mencatat pemakaian.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/dao/product_dao.dart';
import '../../../core/format.dart';
import '../catalog_providers.dart';
import 'product_detail_screen.dart';
import 'product_form_sheet.dart';

class CatalogScreen extends ConsumerWidget {
  final ProductKind initialKind;

  const CatalogScreen({super.key, this.initialKind = ProductKind.menu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialKind == ProductKind.menu ? 0 : 1,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Produk & Stok'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.restaurant_menu), text: 'Menu'),
                Tab(
                  icon: Icon(Icons.inventory_2_outlined),
                  text: 'Bahan & Stok',
                ),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _ProductList(kind: ProductKind.menu),
              _ProductList(kind: ProductKind.bahan),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              final kind = DefaultTabController.of(context).index == 0
                  ? ProductKind.menu
                  : ProductKind.bahan;
              showProductForm(context, kind: kind);
            },
            icon: const Icon(Icons.add),
            label: const Text('Tambah'),
          ),
        ),
      ),
    );
  }
}

class _ProductList extends ConsumerWidget {
  final ProductKind kind;

  const _ProductList({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider(kind));
    final theme = Theme.of(context);

    return products.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                kind == ProductKind.menu
                    ? 'Menu akan muncul otomatis saat kamu mencatat penjualan, '
                          'misalnya "jual nasi ayam dua porsi dua puluh ribu".'
                    : 'Bahan akan muncul otomatis saat kamu mencatat pembelian, '
                          'misalnya "beli ayam lima kilo dua ratus ribu".',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final sorted = kind == ProductKind.bahan
            // Yang menipis naik ke atas supaya tidak terlewat.
            ? ([...items]..sort((a, b) {
                if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
                return a.product.name.compareTo(b.product.name);
              }))
            : items;
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final item = sorted[i];
            final p = item.product;
            return ListTile(
              title: Text(p.name),
              subtitle: Text(
                [
                  if (p.defaultPrice != null)
                    '${formatRupiah(p.defaultPrice!)}${p.unit == null ? '' : '/${p.unit}'}',
                  if (kind == ProductKind.bahan && p.lowStockThreshold != null)
                    'min. ${formatQty(p.lowStockThreshold!, p.unit)}',
                ].join(' · '),
              ),
              trailing: kind == ProductKind.bahan
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.isLow)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.warning_amber,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        Text(
                          formatQty(item.stock, p.unit),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: item.isLow ? theme.colorScheme.error : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => kind == ProductKind.bahan
                  ? Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailScreen(productId: p.id),
                      ),
                    )
                  : showProductForm(context, kind: kind, existing: p),
            );
          },
        );
      },
    );
  }
}
