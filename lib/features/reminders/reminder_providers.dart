/// Pengaturan pengingat dan penyelarasan jadwalnya dengan data toko.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';
import '../../core/format.dart';
import '../debts/debts_providers.dart';
import '../stores/stores_providers.dart';
import 'notification_scheduler.dart';
import 'reminder_planner.dart';

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => LocalNotificationScheduler(),
);

final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class ReminderSettingsController extends AsyncNotifier<ReminderSettings> {
  SettingsDao get _settings => ref.read(settingsDaoProvider);

  @override
  Future<ReminderSettings> build() async {
    final settings = ref.read(settingsDaoProvider);
    final time = await settings.getString(SettingsKeys.reminderTime);
    final parts = (time ?? '').split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
    return ReminderSettings(
      dailyEnabled: await settings.getFlag(SettingsKeys.reminderDaily),
      dueEnabled: await settings.getFlag(SettingsKeys.reminderDue),
      hour: hour != null && hour >= 0 && hour < 24 ? hour : 20,
      minute: minute != null && minute >= 0 && minute < 60 ? minute : 0,
    );
  }

  Future<void> save(ReminderSettings value) async {
    await _settings.setFlag(
      SettingsKeys.reminderDaily,
      value: value.dailyEnabled,
    );
    await _settings.setFlag(SettingsKeys.reminderDue, value: value.dueEnabled);
    await _settings.setString(SettingsKeys.reminderTime, value.timeLabel);
    await _settings.setFlag(SettingsKeys.reminderOfferAnswered, value: true);
    state = AsyncData(value);
  }

  /// Menyalakan pengingat setelah meminta izin. False bila izin ditolak;
  /// pengaturan tidak diubah.
  Future<bool> enable(ReminderSettings value) async {
    if (value.anyEnabled &&
        !await ref.read(notificationSchedulerProvider).requestPermission()) {
      return false;
    }
    await save(value);
    return true;
  }
}

final reminderSettingsProvider =
    AsyncNotifierProvider<ReminderSettingsController, ReminderSettings>(
      ReminderSettingsController.new,
    );

/// Tawaran di beranda: muncul sekali, setelah ada catatan, bila pengingat
/// belum pernah diatur.
final reminderOfferProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(dataRevisionProvider);
  final settings = ref.watch(settingsDaoProvider);
  if (await settings.getFlag(SettingsKeys.reminderOfferAnswered)) return false;
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return false;
  final count = await ref
      .watch(transactionRepositoryProvider)
      .countBetween(
        storeId: storeId,
        from: DateTime.fromMillisecondsSinceEpoch(0),
        to: DateTime.now().add(const Duration(days: 1)),
      );
  return count > 0;
});

/// Menghitung rencana untuk toko aktif lalu menjadwalkannya. Mengembalikan
/// rencananya (berguna untuk tes dan diagnosis).
Future<List<PlannedNotification>> syncReminders(Ref ref) async {
  final scheduler = ref.read(notificationSchedulerProvider);
  final settings = await ref.read(reminderSettingsProvider.future);
  final storeId = ref.read(activeStoreIdProvider);
  if (!settings.anyEnabled || storeId == null) {
    await scheduler.replaceAll(const []);
    return const [];
  }
  final now = ref.read(reminderClockProvider)();
  final today = startOfDay(now);
  final transactions = ref.read(transactionRepositoryProvider);
  final debts = ref.read(debtRepositoryProvider);
  final recordedToday =
      await transactions.countBetween(
        storeId: storeId,
        from: today,
        to: today.add(const Duration(days: 1)),
      ) >
      0;
  final upcoming = settings.dueEnabled
      ? await debts.dueBetween(
          storeId,
          from: today,
          to: today.add(const Duration(days: planDays)),
        )
      : const <Never>[];
  final overdue = settings.dueEnabled
      ? await debts.dueBetween(
          storeId,
          from: DateTime.fromMillisecondsSinceEpoch(0),
          to: today,
        )
      : const <Never>[];
  final plan = planReminders(
    settings: settings,
    now: now,
    storeName: ref.read(activeStoreProvider).value?.name ?? 'SmartToko',
    recordedToday: recordedToday,
    upcomingDue: upcoming,
    overdueCount: overdue.length,
    overdueAmount: overdue.fold(0, (sum, d) => sum + d.outstanding),
  );
  await scheduler.replaceAll(plan);
  return plan;
}

/// Pemicu yang bisa dipanggil dari widget (WidgetRef) maupun tes.
final reminderSyncProvider =
    Provider<Future<List<PlannedNotification>> Function()>(
      (ref) =>
          () => syncReminders(ref),
    );
