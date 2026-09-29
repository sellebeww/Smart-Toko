/// Profil toko: sumber kebenarannya ada di tabel `stores` di Supabase (bukan
/// SQLite lokal), karena satu akun boleh punya banyak toko yang harus
/// kelihatan dari perangkat mana pun setelah login.
library;

import '../../verification/domain/verification_status.dart';

enum StoreCategory {
  warteg,
  warungKelontong,
  tokoOnline,
  pedagangPasar,
  lainnya;

  String get label => switch (this) {
    StoreCategory.warteg => 'Warteg',
    StoreCategory.warungKelontong => 'Warung Kelontong',
    StoreCategory.tokoOnline => 'Toko Online',
    StoreCategory.pedagangPasar => 'Pedagang Pasar',
    StoreCategory.lainnya => 'Lainnya',
  };

  static StoreCategory fromName(String? value) => StoreCategory.values
      .firstWhere((c) => c.name == value, orElse: () => StoreCategory.lainnya);
}

class StoreProfile {
  final String id;
  final String ownerUid;
  final String name;
  final StoreCategory category;
  final String address;
  final DateTime createdAt;
  final StoreVerificationStatus verificationStatus;
  final String? rejectionReason;

  const StoreProfile({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.category,
    required this.address,
    required this.createdAt,
    this.verificationStatus = StoreVerificationStatus.unverified,
    this.rejectionReason,
  });

  /// [row] adalah baris mentah dari Postgrest — kolomnya snake_case
  /// (owner_uid, created_at, dst.), beda dari nama field Dart di kelas ini.
  factory StoreProfile.fromRow(Map<String, dynamic> row) {
    final createdAt = row['created_at'];
    return StoreProfile(
      id: row['id'] as String,
      ownerUid: row['owner_uid'] as String,
      name: row['name'] as String,
      category: StoreCategory.fromName(row['category'] as String?),
      address: row['address'] as String? ?? '',
      createdAt: createdAt is String
          ? DateTime.parse(createdAt)
          : DateTime.now(),
      verificationStatus: StoreVerificationStatus.fromName(
        row['verification_status'] as String?,
      ),
      rejectionReason: row['rejection_reason'] as String?,
    );
  }
}
