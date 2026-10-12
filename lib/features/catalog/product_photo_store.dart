/// Penyimpanan foto barang di HP ini.
///
/// Foto diperkecil saat diambil (lihat image_picker di form), lalu disalin ke
/// folder aplikasi supaya tidak hilang saat cache dibersihkan sistem.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProductPhotoStore {
  final Future<Directory> Function() _baseDir;

  ProductPhotoStore({Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _baseDir()).path, 'product_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Memindahkan [picked] ke folder foto barang dan mengembalikan path-nya.
  /// Nama berkas memuat waktu, supaya gambar lama di cache layar tidak
  /// tertampil setelah foto diganti.
  Future<String> adopt(File picked, String productId) async {
    final dir = await _dir();
    final target = p.join(
      dir.path,
      '${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await picked.copy(target);
    try {
      await picked.delete();
    } catch (_) {
      // Salinan di cache; sistem akan membersihkannya.
    }
    return target;
  }

  /// Menghapus berkas foto lama. Path di luar folder foto tidak disentuh.
  Future<void> delete(String? path) async {
    if (path == null) return;
    final dir = await _dir();
    if (!p.isWithin(dir.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
