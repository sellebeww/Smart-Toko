/// Penyimpan catatan ucapan yang gagal diurai.
///
/// Catatan ini LOKAL. Kolom `shared` tetap 0 sampai pengguna menyetujui
/// pengiriman contoh ucapan untuk perbaikan parser — persetujuan yang terpisah
/// dari sakelar cadangan, karena transkrip bisa memuat hal pribadi.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../features/voice_parser/logging/parse_failure_logger.dart';

class ParseFailureDao implements ParseFailureLogger {
  final DatabaseExecutor db;
  final Uuid uuid;

  ParseFailureDao(this.db, {Uuid? uuid}) : uuid = uuid ?? const Uuid();

  @override
  Future<void> record(ParseFailure failure) async {
    await db.insert('parse_failures', {
      'id': uuid.v4(),
      'transcript': failure.transcript,
      'stt_confidence': failure.sttConfidence,
      'parser_version': failure.parserVersion,
      'reason': failure.reasonLabel,
      'unmatched_tokens': failure.unmatchedTokens.join(' '),
      'created_at': failure.occurredAt.millisecondsSinceEpoch,
      'shared': 0,
    });
  }

  /// Pola kegagalan tersering, dasar untuk memperbaiki aturan parser.
  Future<List<({String reason, int count})>> topReasons({
    int limit = 10,
  }) async {
    final rows = await db.rawQuery(
      'SELECT reason, COUNT(*) AS c FROM parse_failures '
      'GROUP BY reason ORDER BY c DESC LIMIT ?',
      [limit],
    );
    return [
      for (final row in rows)
        (reason: row['reason']! as String, count: (row['c']! as num).toInt()),
    ];
  }

  Future<int> count() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM parse_failures');
    return (rows.first['c']! as num).toInt();
  }

  Future<void> deleteAll() async => db.delete('parse_failures');
}
