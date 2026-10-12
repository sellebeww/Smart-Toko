/// Foto kecil barang, atau [fallback] bila tidak ada fotonya di HP ini.
library;

import 'dart:io';

import 'package:flutter/material.dart';

class ProductThumb extends StatelessWidget {
  final String? path;
  final double size;
  final Widget fallback;

  const ProductThumb({
    super.key,
    required this.path,
    this.size = 44,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    final p = path;
    // Foto dari HP lain tidak pernah ikut sinkron, jadi path bisa saja
    // kosong atau berkasnya sudah dihapus.
    if (p == null || !File(p).existsSync()) return fallback;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(p),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * ratio).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
