/// Upload berkas verifikasi (KTP, foto toko, selfie, NIB) ke Supabase
/// Storage, bucket `verifications`.
///
/// Path-nya `{ownerUid}/{storeId}/...` supaya cocok dengan storage policy:
/// pemilik hanya bisa menulis ke folder tokonya sendiri selama toko itu belum
/// diajukan/disetujui, dan hanya admin yang bisa membacanya selain pemilik
/// (lihat skrip SQL setup). Aplikasi pemilik tidak pernah menampilkan ulang
/// KTP/selfie, dan berkas ini tidak pernah ikut proses export mana pun.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

const String verificationBucket = 'verifications';

/// Nama berkas tiap dokumen di folder `{ownerUid}/{storeId}/`.
enum VerificationDocument {
  ktp('ktp.jpg', 'KTP'),
  storePhoto('store_photo.jpg', 'Foto toko'),
  selfie('selfie.jpg', 'Selfie + KTP'),
  nib('nib.jpg', 'NIB / izin usaha');

  final String fileName;
  final String label;

  const VerificationDocument(this.fileName, this.label);
}

class VerificationRepository {
  final SupabaseClient _client;

  VerificationRepository(this._client);

  Future<void> _upload(
    String ownerUid,
    String storeId,
    String fileName,
    File file,
  ) async {
    await _client.storage
        .from(verificationBucket)
        .upload(
          '$ownerUid/$storeId/$fileName',
          file,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            // Slot yang sama boleh diunggah ulang saat pengguna mengganti foto
            // atau mengajukan verifikasi lagi setelah ditolak.
            upsert: true,
          ),
        );
  }

  Future<void> upload(
    String ownerUid,
    String storeId,
    VerificationDocument document,
    File file,
  ) => _upload(ownerUid, storeId, document.fileName, file);

  /// Untuk panel admin: tautan sementara (10 menit) ke berkas yang
  /// diunggah, atau null bila berkas itu tidak ada (NIB bersifat opsional).
  Future<Map<VerificationDocument, String>> signedUrls(
    String ownerUid,
    String storeId,
  ) async {
    final bucket = _client.storage.from(verificationBucket);
    final existing = {
      for (final object in await bucket.list(path: '$ownerUid/$storeId'))
        object.name,
    };
    return {
      for (final document in VerificationDocument.values)
        if (existing.contains(document.fileName))
          document: await bucket.createSignedUrl(
            '$ownerUid/$storeId/${document.fileName}',
            600,
          ),
    };
  }
}
