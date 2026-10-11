/// Penyelarasan pengingat dengan data toko dan pengaturannya.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/reminders/notification_scheduler.dart';
import 'package:smart_toko/features/reminders/reminder_planner.dart';
import 'package:smart_toko/features/reminders/reminder_providers.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

class FakeScheduler implements NotificationScheduler {
  bool grant = true;
  int permissionRequests = 0;
  List<PlannedNotification>? scheduled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async =>
      scheduled = plan;

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> launchPayload() async => null;
}

class _FixedStore extends ActiveStoreId {
  final String id;
  _FixedStore(this.id);

  @override
  String? build() => id;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('id_ID');
  });

  late AppDatabase database;
  late FakeScheduler scheduler;
  late ProviderContainer container;
  late String storeId;
  final now = DateTime(2026, 10, 12, 9);

  Future<void> record({
    DateTime? at,
    bool credit = false,
    String? contactId,
    DateTime? dueAt,
  }) => TransactionRepository(database: database).save(
    confirmDraftByUser(
      draft: TransactionDraft(
        direction: const DraftField<TxDirection>.entered(TxDirection.masuk),
        items: const [
          DraftItem(
            name: DraftField<String>.entered('nasi'),
            qty: DraftField<int>.entered(1),
            unitPrice: DraftField<int>.entered(20000),
          ),
        ],
        occurredAt: at ?? now,
        source: TxSource.manual,
        onCredit: credit,
        contactId: contactId,
        dueAt: dueAt,
      ),
      editedFields: const {},
    )!,
    storeId: storeId,
  );

  setUp(() async {
    // Berkas sendiri per tes: path in-memory yang sama bisa mengembalikan
    // instans tes sebelumnya bila penutupannya belum tuntas.
    final dir = await Directory.systemTemp.createTemp('smarttoko_reminder');
    addTearDown(() => dir.delete(recursive: true));
    database = AppDatabase();
    await database.open(overridePath: '${dir.path}/app.db');
    storeId = (await StoreDao(database.db).create(name: 'Warung')).id;
    scheduler = FakeScheduler();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        activeStoreIdProvider.overrideWith(() => _FixedStore(storeId)),
        notificationSchedulerProvider.overrideWithValue(scheduler),
        reminderClockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  ReminderSettingsController controller() =>
      container.read(reminderSettingsProvider.notifier);
  Future<List<PlannedNotification>> sync() =>
      container.read(reminderSyncProvider)();

  test('bawaannya mati, dan sinkron membersihkan jadwal', () async {
    final settings = await container.read(reminderSettingsProvider.future);

    expect(settings.anyEnabled, isFalse);
    expect(await sync(), isEmpty);
    expect(scheduler.scheduled, isEmpty);
  });

  test('menyalakan meminta izin lalu menyimpan pengaturan', () async {
    await container.read(reminderSettingsProvider.future);

    final ok = await controller().enable(
      const ReminderSettings(dailyEnabled: true, hour: 21),
    );

    expect(ok, isTrue);
    expect(scheduler.permissionRequests, 1);
    container.invalidate(reminderSettingsProvider);
    final reloaded = await container.read(reminderSettingsProvider.future);
    expect(reloaded.dailyEnabled, isTrue);
    expect(reloaded.hour, 21);
  });

  test('izin ditolak: pengaturan tidak berubah', () async {
    await container.read(reminderSettingsProvider.future);
    scheduler.grant = false;

    final ok = await controller().enable(
      const ReminderSettings(dailyEnabled: true),
    );

    expect(ok, isFalse);
    expect(
      container.read(reminderSettingsProvider).value!.dailyEnabled,
      isFalse,
    );
  });

  test('sudah mencatat hari ini: pengingat hari ini dilewati', () async {
    await container.read(reminderSettingsProvider.future);
    await controller().save(const ReminderSettings(dailyEnabled: true));

    expect((await sync()).first.at, DateTime(2026, 10, 12, 20));

    await record();
    expect((await sync()).first.at, DateTime(2026, 10, 13, 20));
    expect(scheduler.scheduled!.first.at, DateTime(2026, 10, 13, 20));
  });

  test('kasbon jatuh tempo masuk jadwal pagi', () async {
    await container.read(reminderSettingsProvider.future);
    await controller().save(const ReminderSettings(dueEnabled: true));
    final sari = await ContactDao(database.db).create(
      storeId: storeId,
      kind: ContactKind.pelanggan,
      name: 'Bu Sari',
      now: now,
    );
    await record(
      at: DateTime(2026, 10, 1),
      credit: true,
      contactId: sari.id,
      dueAt: DateTime(2026, 10, 14),
    );

    final plan = await sync();

    expect(plan, hasLength(1));
    expect(plan.single.at, DateTime(2026, 10, 14, dueReminderHour));
    expect(plan.single.body, contains('Bu Sari'));
  });

  test('menjawab tawaran di beranda menyembunyikannya', () async {
    await record();
    expect(await container.read(reminderOfferProvider.future), isTrue);

    await container.read(reminderSettingsProvider.future);
    await controller().save(const ReminderSettings());
    container.invalidate(reminderOfferProvider);

    expect(await container.read(reminderOfferProvider.future), isFalse);
  });

  test('tawaran tidak muncul sebelum ada catatan', () async {
    expect(await container.read(reminderOfferProvider.future), isFalse);
  });

  test('mematikan semuanya membersihkan jadwal', () async {
    await container.read(reminderSettingsProvider.future);
    await controller().save(const ReminderSettings(dailyEnabled: true));
    expect(await sync(), isNotEmpty);

    await controller().save(const ReminderSettings());
    await sync();

    expect(scheduler.scheduled, isEmpty);
  });
}
