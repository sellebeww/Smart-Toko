/// Status verifikasi kepemilikan toko.
///
/// SELALU opsional: status apa pun di sini tidak pernah membatasi fungsi
/// pencatatan transaksi. Ini cuma menentukan apakah toko dapat lencana
/// "Terverifikasi" atau tidak.
library;

enum StoreVerificationStatus {
  unverified,
  pending,
  verified,
  rejected;

  String get label => switch (this) {
    StoreVerificationStatus.unverified => 'Belum Diverifikasi',
    StoreVerificationStatus.pending => 'Menunggu Verifikasi',
    StoreVerificationStatus.verified => 'Terverifikasi',
    StoreVerificationStatus.rejected => 'Ditolak',
  };

  static StoreVerificationStatus fromName(String? value) =>
      StoreVerificationStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => StoreVerificationStatus.unverified,
      );
}
