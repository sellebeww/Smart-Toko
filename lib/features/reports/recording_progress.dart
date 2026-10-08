import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/ui/figma_icon.dart';

/// Hari kalender, bukan durasi 24 jam, agar aman di zona waktu dengan DST.
int recordingStreak(Set<DateTime> days, DateTime now) {
  var cursor = startOfDay(now);
  if (!days.contains(cursor)) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var count = 0;
  while (days.contains(cursor)) {
    count++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return count;
}

final recordingDaysProvider = FutureProvider.autoDispose<Set<DateTime>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final store = ref.watch(activeStoreIdProvider);
  if (store == null) return {};
  final rows = await ref.watch(appDatabaseProvider).db.rawQuery(
    "SELECT DISTINCT date(occurred_at / 1000, 'unixepoch', 'localtime') AS day FROM transactions WHERE store_id = ? AND occurred_at < ?",
    [store, DateTime.now().millisecondsSinceEpoch],
  );
  return {for (final row in rows) DateTime.parse(row['day'] as String)};
});

class RecordingProgressCard extends ConsumerWidget {
  final bool expanded;
  const RecordingProgressCard({super.key, this.expanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(recordingDaysProvider);
    return days.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (days) {
        final now = DateTime.now();
        final today = startOfDay(now);
        final streak = recordingStreak(days, now);
        final recorded = days.contains(today);
        return Card(
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recorded
                      ? 'Hari ini sudah tercatat!'
                      : 'Mulai kebiasaan baik',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const FigmaIcon('d2b81'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        streak == 0
                            ? 'Satu catatan kecil, langkah besar untuk usaha.'
                            : '$streak hari berturut-turut mencatat. Pertahankan, ya!',
                        style: const TextStyle(
                          color: Color(0xFF176448),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (var i = 6; i >= 0; i--)
                        Expanded(
                          child: _Day(
                            day: DateTime(
                              today.year,
                              today.month,
                              today.day - i,
                            ),
                            recorded: days.contains(
                              DateTime(today.year, today.month, today.day - i),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: (streak / 30).clamp(0, 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    streak >= 30
                        ? 'Target 30 hari tercapai. Hebat!'
                        : '$streak dari 30 hari menuju kebiasaan mencatat rutin.',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Day extends StatelessWidget {
  final DateTime day;
  final bool recorded;
  const _Day({required this.day, required this.recorded});

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${formatShortDate(day)}: ${recorded ? 'sudah mencatat' : 'belum mencatat'}',
    child: Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: recorded
              ? const Color(0xFF176448)
              : const Color(0xFFE2E7DE),
          child: recorded
              ? const FigmaIcon('92a51')
              : const Icon(Icons.remove, size: 16),
        ),
        const SizedBox(height: 6),
        Text('${day.day}', style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class RecordingProgressScreen extends StatelessWidget {
  const RecordingProgressScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Progres pencatatan')),
    body: ListView(
      children: const [
        RecordingProgressCard(expanded: true),
        Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Progres dihitung dari tanggal transaksi yang tercatat di toko ini. Catat setiap ada penjualan atau pengeluaran agar ringkasan usaha tetap lengkap.',
          ),
        ),
      ],
    ),
  );
}
