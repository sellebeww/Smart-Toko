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
import '../../../core/ui/figma_icon.dart';
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
        final lowCount = sorted.where((item) => item.isLow).length;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          itemCount: sorted.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kind == ProductKind.bahan && lowCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1DF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const FigmaIcon('65ded'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$lowCount bahan perlu dibeli',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'Periksa stok sebelum mulai masak.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFAD642C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          kind == ProductKind.bahan
                              ? 'Persediaan dapur'
                              : 'Daftar menu',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${sorted.length} ${kind == ProductKind.bahan ? 'bahan' : 'menu'}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }
            final i = index - 1;
            final item = sorted[i];
            final p = item.product;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: item.isLow
                      ? const Color(0xFFEAD6B9)
                      : const Color(0xFFE2E7DE),
                ),
              ),
              child: InkWell(
                onTap: () => kind == ProductKind.bahan
                    ? Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductDetailScreen(productId: p.id),
                        ),
                      )
                    : showProductForm(context, kind: kind, existing: p),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (kind == ProductKind.menu) ...[
                            const FigmaIcon('9602a'),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              p.name,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (kind == ProductKind.bahan)
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  formatQty(item.stock, p.unit),
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: item.isLow
                                        ? const Color(0xFFAD642C)
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.more_vert, size: 20),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (kind == ProductKind.bahan)
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              p.lowStockThreshold == null
                                  ? 'Batas minimum belum diatur'
                                  : 'Batas minimum ${formatQty(p.lowStockThreshold!, p.unit)}',
                              style: theme.textTheme.bodySmall,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: item.isLow
                                    ? const Color(0xFFFFF1DF)
                                    : const Color(0xFFE8F2E9),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                item.isLow
                                    ? 'Stok menipis'
                                    : p.lowStockThreshold == null
                                    ? 'Atur batas'
                                    : 'Aman',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: item.isLow
                                      ? const Color(0xFFAD642C)
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          p.defaultPrice == null
                              ? 'Harga belum diatur'
                              : '${formatRupiah(p.defaultPrice!)}${p.unit == null ? '' : ' / ${p.unit}'}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
