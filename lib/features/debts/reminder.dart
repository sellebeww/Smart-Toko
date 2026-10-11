/// Pesan pengingat tagihan dan tautan WhatsApp-nya.
///
/// Aplikasi tidak mengirim apa pun sendiri: pesan hanya disiapkan, lalu
/// pengguna yang menekan kirim di WhatsApp. Jadi tidak ada data pelanggan
/// yang keluar dari HP tanpa tindakan pengguna.
library;

import '../../core/format.dart';

/// Pesan sopan yang menyebut nama toko, jumlah, dan sejak kapan.
String buildReminderMessage({
  required String contactName,
  required String storeName,
  required int outstanding,
  required int openCount,
  required DateTime since,
}) {
  final count = openCount > 1 ? ' ($openCount transaksi)' : '';
  return 'Halo $contactName, ini pengingat dari $storeName. '
      'Masih ada sisa pembayaran ${formatRupiah(outstanding)}$count '
      'sejak ${formatShortDate(since)}. '
      'Mohon konfirmasinya ya. Terima kasih 🙏';
}

/// Nomor Indonesia ke format internasional tanpa plus untuk wa.me.
/// "0812-3456-789" → "628123456789". Null bila bukan nomor yang masuk akal.
String? normalizeIndonesianPhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) digits = digits.substring(1);
  if (digits.startsWith('62')) {
    // sudah internasional
  } else if (digits.startsWith('0')) {
    digits = '62${digits.substring(1)}';
  } else if (digits.startsWith('8')) {
    digits = '62$digits';
  } else {
    return null;
  }
  // Nomor seluler Indonesia: 62 + 9 sampai 12 digit.
  if (!RegExp(r'^62\d{8,13}$').hasMatch(digits)) return null;
  return digits;
}

/// Tautan wa.me berisi pesan; null bila nomornya tidak valid.
Uri? whatsappLink(String? phone, String message) {
  final number = normalizeIndonesianPhone(phone);
  if (number == null) return null;
  return Uri.https('wa.me', '/$number', {'text': message});
}
