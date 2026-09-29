/// Upload berkas verifikasi (KTP, foto toko, selfie, NIB) ke Supabase
/// Storage, bucket `verifications`.
///
/// Path-nya `{ownerUid}/{storeId}/...` supaya cocok dengan storage policy:
/// hanya pemilik uid itu yang boleh baca/tulis (lihat skrip SQL setup). File-
/// file ini TIDAK PERNAH dibaca balik oleh aplikasi (tidak ada layar yang
/// menampilkan ulang KTP/selfie) dan tidak pernah ikut proses export mana pun.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

const String verificationBucket = 'verifications';

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

  Future<void> uploadKtp(String ownerUid, String storeId, File file) =>
      _upload(ownerUid, storeId, 'ktp.jpg', file);

  Future<void> uploadStorePhoto(String ownerUid, String storeId, File file) =>
      _upload(ownerUid, storeId, 'store_photo.jpg', file);

  Future<void> uploadSelfie(String ownerUid, String storeId, File file) =>
      _upload(ownerUid, storeId, 'selfie.jpg', file);

  Future<void> uploadNib(String ownerUid, String storeId, File file) =>
      _upload(ownerUid, storeId, 'nib.jpg', file);
}
