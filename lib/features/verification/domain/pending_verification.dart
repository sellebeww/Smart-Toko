/// Satu pengajuan verifikasi yang menunggu ditinjau admin.
library;

import '../../stores/domain/store_profile.dart';

class PendingVerification {
  final String storeId;
  final String ownerUid;
  final String? ownerEmail;
  final String name;
  final StoreCategory category;
  final String address;
  final DateTime? submittedAt;

  const PendingVerification({
    required this.storeId,
    required this.ownerUid,
    required this.name,
    required this.category,
    required this.address,
    this.ownerEmail,
    this.submittedAt,
  });

  /// Baris dari fungsi Postgres `admin_pending_verifications`.
  factory PendingVerification.fromRow(Map<String, dynamic> row) {
    final submitted = row['submitted_at'];
    return PendingVerification(
      storeId: row['store_id'] as String,
      ownerUid: row['owner_uid'] as String,
      ownerEmail: row['owner_email'] as String?,
      name: row['name'] as String,
      category: StoreCategory.fromName(row['category'] as String?),
      address: row['address'] as String? ?? '',
      submittedAt: submitted is String
          ? DateTime.parse(submitted).toLocal()
          : null,
    );
  }
}
