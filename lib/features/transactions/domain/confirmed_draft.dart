/// Gerbang tunggal antara hasil penguraian dan penyimpanan.
///
/// [TransactionRepository.save] hanya menerima [ConfirmedDraft], dan
/// konstruktor [ConfirmedDraft] bersifat privat pada pustaka ini. Artinya tidak
/// ada jalur kode dari audio ke basis data yang melewati manusia — "simpan
/// otomatis dari suara" bukan sekadar tidak diimplementasikan, melainkan tidak
/// bisa ditulis tanpa melewati [confirmDraftByUser].
///
/// Batasnya perlu disebut jujur: privasi Dart berlaku per-pustaka, jadi
/// [confirmDraftByUser] sendiri tetap dapat dipanggil dari berkas mana pun.
/// Karena itu ada pengujian arsitektur yang gagal bila ada berkas lain selain
/// pengendali layar konfirmasi yang memanggilnya.
library;

import 'transaction_draft.dart';

class ConfirmedDraft {
  final TransactionDraft draft;
  final DateTime confirmedAt;

  /// Field yang benar-benar disunting manusia sebelum menyimpan.
  ///
  /// Ini bahan evaluasi kualitas parser: field yang sering dikoreksi menunjuk
  /// aturan mana yang perlu diperbaiki.
  final Set<String> editedFields;

  const ConfirmedDraft._({
    required this.draft,
    required this.confirmedAt,
    required this.editedFields,
  });
}

/// Satu-satunya cara memperoleh [ConfirmedDraft].
///
/// Mengembalikan null bila draft belum lengkap, sehingga kelengkapan data
/// terjamin tanpa perlu mematikan aplikasi pengguna.
ConfirmedDraft? confirmDraftByUser({
  required TransactionDraft draft,
  required Set<String> editedFields,
  DateTime? confirmedAt,
}) {
  if (!draft.isComplete) return null;
  return ConfirmedDraft._(
    draft: draft,
    confirmedAt: confirmedAt ?? DateTime.now(),
    editedFields: Set.unmodifiable(editedFields),
  );
}
