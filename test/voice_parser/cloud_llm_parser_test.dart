import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/voice_parser/domain/parse_result.dart';
import 'package:smart_toko/features/voice_parser/llm/cloud_llm_parser.dart';
import 'package:smart_toko/features/voice_parser/llm/llm_parser.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

void main() {
  final ruleResult = const RuleBasedParser().parse('jual sesuatu');

  Future<LlmParseOutcome> refine(LlmInvoker invoke) =>
      CloudLlmParser(invoke: invoke).refine(
        transcript: 'jual nasi rames dua lima belas ribu',
        ruleResult: ruleResult,
      );

  test('hasil server dipetakan dan keyakinannya dibatasi', () async {
    final outcome = await refine(
      (_) async => {
        'arah': 'masuk',
        'barang': [
          {'nama': 'nasi rames', 'jumlah': 2, 'harga_satuan': 15000},
        ],
        'keyakinan': 0.99,
      },
    );

    final result = (outcome as LlmParsed).result;
    expect(result.source, ParseSource.llm);
    expect(result.direction.value, TxDirection.masuk);
    expect(result.items.single.name.value, 'nasi rames');
    expect(result.items.single.qty.value, 2);
    expect(result.items.single.unitPrice.value, 15000);
    expect(result.direction.confidence.value, maxLlmConfidence);
  });

  test(
    'arah tidak yakin dan harga kosong tetap kosong, tidak ditebak',
    () async {
      final outcome = await refine(
        (_) async => {
          'arah': 'tidak_yakin',
          'barang': [
            {'nama': 'gula', 'jumlah': null, 'harga_satuan': null},
            {'nama': null, 'jumlah': 1, 'harga_satuan': null},
          ],
          'keyakinan': 0.4,
        },
      );

      final result = (outcome as LlmParsed).result;
      expect(result.direction.isPresent, isFalse);
      expect(result.items, hasLength(1));
      expect(result.items.single.qty.value, 1);
      expect(result.items.single.unitPrice.isPresent, isFalse);
    },
  );

  test('batas harian dari server menjadi alasan yang bisa dibaca', () async {
    final outcome = await refine(
      (_) async => throw const FunctionException(status: 429),
    );
    expect(outcome, isA<LlmUnavailable>());
    expect((outcome as LlmUnavailable).reason, contains('Batas harian'));
  });

  test('kegagalan apa pun tidak pernah melempar', () async {
    final outcome = await refine((_) async => throw Exception('boom'));
    expect(outcome, isA<LlmUnavailable>());
  });
}
