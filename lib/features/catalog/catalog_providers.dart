/// Provider katalog menu/bahan beserta stok.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/product_dao.dart';

class ProductWithStock {
  final ProductRecord product;

  /// Hanya bermakna untuk bahan; menu tidak dilacak stoknya.
  final int stock;

  const ProductWithStock(this.product, this.stock);

  bool get isLow {
    final threshold = product.lowStockThreshold;
    return product.kind == ProductKind.bahan &&
        threshold != null &&
        stock <= threshold;
  }
}

final productsProvider = FutureProvider.autoDispose
    .family<List<ProductWithStock>, ProductKind>((ref, kind) async {
      ref.watch(dataRevisionProvider);
      final storeId = ref.watch(activeStoreIdProvider);
      if (storeId == null) return const [];
      final dao = ref.watch(productDaoProvider);
      final products = await dao.list(storeId: storeId, kind: kind);
      final levels = kind == ProductKind.bahan
          ? await dao.stockLevels(storeId)
          : const <String, int>{};
      return [for (final p in products) ProductWithStock(p, levels[p.id] ?? 0)];
    });

/// Bahan yang stoknya di bawah batas, paling kritis dulu.
final lowStockProvider = FutureProvider.autoDispose<List<ProductWithStock>>((
  ref,
) async {
  final all = await ref.watch(productsProvider(ProductKind.bahan).future);
  return all.where((p) => p.isLow).toList()
    ..sort((a, b) => a.stock.compareTo(b.stock));
});
