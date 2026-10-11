/// Perencana pengingat: kapan dan apa isinya.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/debts/data/debt_repository.dart';
import 'package:smart_toko/features/reminders/reminder_planner.dart';

DueDebt due(
  String name,
  DateTime at, {
  int amount = 20000,
  TxDirection direction = TxDirection.masuk,
}) => DueDebt(
  transactionId: name,
  contactName: name,
  direction: direction,
  outstanding: amount,
  dueAt: at,
);

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  const daily = ReminderSettings(dailyEnabled: true, hour: 20, minute: 30);
  const dueOnly = ReminderSettings(dueEnabled: true);
  final morning = DateTime(2026, 10, 12, 7, 0);

  List<PlannedNotification> plan({
    ReminderSettings settings = daily,
    DateTime? now,
    bool recordedToday = false,
    List<DueDebt> upcoming = const [],
    int overdueCount = 0,
    int overdueAmount = 0,
  }) => planReminders(
    settings: settings,
    now: now ?? morning,
    storeName: 'Warung Bahari',
    recordedToday: recordedToday,
    upcomingDue: upcoming,
    overdueCount: overdueCount,
    overdueAmount: overdueAmount,
  );

  test('semua mati: tidak ada yang dijadwalkan', () {
    expect(plan(settings: const ReminderSettings()), isEmpty);
  });

  group('pengingat mencatat', () {
    test('tujuh hari ke depan pada jam yang dipilih', () {
      final result = plan();

      expect(result, hasLength(planDays));
      expect(result.first.at, DateTime(2026, 10, 12, 20, 30));
      expect(result.last.at, DateTime(2026, 10, 18, 20, 30));
      expect(result.map((n) => n.id).toSet(), hasLength(planDays));
      expect(result.first.title, contains('Warung Bahari'));
      expect(result.first.payload, 'record');
    });

    test('hari ini dilewati bila sudah mencatat', () {
      final result = plan(recordedToday: true);

      expect(result.first.at, DateTime(2026, 10, 13, 20, 30));
      expect(result, hasLength(planDays - 1));
    });

    test('jam hari ini yang sudah lewat tidak dijadwalkan', () {
      final result = plan(now: DateTime(2026, 10, 12, 21));

      expect(result.first.at, DateTime(2026, 10, 13, 20, 30));
    });

    test('isinya berganti-ganti antarhari', () {
      final bodies = plan().map((n) => n.body).toSet();

      expect(bodies.length, greaterThan(1));
    });
  });

  group('pengingat jatuh tempo', () {
    test('pagi hari pada tanggal jatuh tempo, dipisah tagih dan bayar', () {
      final result = plan(
        settings: dueOnly,
        upcoming: [
          due('Bu Sari', DateTime(2026, 10, 14), amount: 40000),
          due(
            'Toko Maju',
            DateTime(2026, 10, 14),
            amount: 250000,
            direction: TxDirection.keluar,
          ),
        ],
      );

      expect(result, hasLength(1));
      final n = result.single;
      expect(n.at, DateTime(2026, 10, 14, dueReminderHour));
      expect(n.title, 'Jatuh tempo 14 Okt 2026');
      expect(n.body, contains('Tagih: Bu Sari Rp40.000'));
      expect(n.body, contains('Bayar: Toko Maju Rp250.000'));
      expect(n.payload, 'debts');
    });

    test('jatuh tempo hari ini memakai judul "hari ini"', () {
      final result = plan(
        settings: dueOnly,
        upcoming: [due('Bu Sari', DateTime(2026, 10, 12))],
      );

      expect(result.single.title, 'Jatuh tempo hari ini');
    });

    test('lebih dari dua nama diringkas', () {
      final day = DateTime(2026, 10, 13);
      final result = plan(
        settings: dueOnly,
        upcoming: [due('A', day), due('B', day), due('C', day), due('D', day)],
      );

      expect(result.single.body, contains('dan 2 lainnya'));
    });

    test('jam pagi yang sudah lewat hari ini tidak dijadwalkan', () {
      final result = plan(
        settings: dueOnly,
        now: DateTime(2026, 10, 12, 9),
        upcoming: [due('Bu Sari', DateTime(2026, 10, 12))],
      );

      expect(result, isEmpty);
    });

    test('kasbon telat disebut sekali saja, di pagi terdekat', () {
      final result = plan(
        settings: dueOnly,
        now: DateTime(2026, 10, 12, 10),
        upcoming: [due('Bu Sari', DateTime(2026, 10, 15))],
        overdueCount: 2,
        overdueAmount: 75000,
      );

      expect(result, hasLength(2));
      expect(result.first.at, DateTime(2026, 10, 13, dueReminderHour));
      expect(result.first.title, 'Ada kasbon yang lewat jatuh tempo');
      expect(result.first.body, contains('2 kasbon sudah telat'));
      expect(result.last.body, isNot(contains('telat')));
    });

    test('jatuh tempo di luar tujuh hari tidak dijadwalkan', () {
      final result = plan(
        settings: dueOnly,
        upcoming: [due('Bu Sari', DateTime(2026, 10, 30))],
      );

      expect(result, isEmpty);
    });
  });

  test('gabungan diurutkan menurut waktu dan id-nya unik', () {
    final result = plan(
      settings: const ReminderSettings(
        dailyEnabled: true,
        hour: 20,
        dueEnabled: true,
      ),
      upcoming: [due('Bu Sari', DateTime(2026, 10, 12))],
    );

    expect(result.first.kind, ReminderKind.due);
    expect(result[1].kind, ReminderKind.daily);
    expect(result.map((n) => n.id).toSet().length, result.length);
    for (var i = 1; i < result.length; i++) {
      expect(result[i].at.isBefore(result[i - 1].at), isFalse);
    }
  });

  test('label jam selalu dua digit', () {
    expect(const ReminderSettings(hour: 7, minute: 5).timeLabel, '07:05');
  });
}
