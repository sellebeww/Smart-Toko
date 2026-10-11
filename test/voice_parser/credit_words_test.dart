/// Kata kasbon pada ucapan hanya menjadi petunjuk "belum dibayar", dan tidak
/// boleh bocor menjadi nama barang atau token tak dikenal.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

void main() {
  const parser = RuleBasedParser();

  test('ucapan tunai tidak ditandai kasbon', () {
    final result = parser.parse('jual nasi goreng dua lima belas ribu');

    expect(result.onCredit, isFalse);
  });

  for (final phrase in [
    'jual nasi goreng dua lima belas ribu ngutang',
    'ngutang jual nasi goreng dua lima belas ribu',
    'jual nasi goreng dua lima belas ribu kasbon',
    'jual nasi goreng dua lima belas ribu belum bayar',
    'jual nasi goreng dua lima belas ribu bayar nanti',
    'jual nasi goreng dua lima belas ribu hutang',
  ]) {
    test('"$phrase" ditandai kasbon tanpa merusak barangnya', () {
      final result = parser.parse(phrase);

      expect(result.onCredit, isTrue);
      expect(result.items, hasLength(1));
      expect(result.items.single.name.value, 'nasi goreng');
      expect(result.items.single.qty.value, 2);
      expect(result.unmatchedTokens, isEmpty);
    });
  }

  test('petunjuk kasbon terbawa ke draf, tapi kontak tetap wajib', () {
    final result = parser.parse('jual nasi goreng dua lima belas ribu ngutang');

    final draft = TransactionDraft.fromParseResult(result);

    expect(draft.onCredit, isTrue);
    expect(draft.isCredit, isTrue);
    expect(draft.isComplete, isFalse, reason: 'belum ada yang dipilih');
    expect(draft.copyWith(contactId: 'sari').isComplete, isTrue);
  });
}
