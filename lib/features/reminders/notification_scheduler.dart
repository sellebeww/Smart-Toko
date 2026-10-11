/// Penjadwal notifikasi lokal. Dibungkus antarmuka supaya logika pengingat
/// bisa diuji tanpa plugin.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

abstract class NotificationScheduler {
  /// Meminta izin notifikasi. True bila diizinkan.
  Future<bool> requestPermission();

  /// Mengganti semua notifikasi terjadwal dengan [plan]. Notifikasi yang
  /// sudah tampil tidak dihapus.
  Future<void> replaceAll(List<PlannedNotification> plan);

  /// Payload notifikasi yang diketuk saat aplikasi berjalan.
  Stream<String> get taps;

  /// Payload notifikasi yang membuka aplikasi dari keadaan tertutup.
  Future<String?> launchPayload();
}

class LocalNotificationScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController.broadcast();
  Future<void>? _ready;

  static const _channelId = 'pengingat';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Pengingat',
      channelDescription: 'Pengingat mencatat dan jatuh tempo kasbon',
      icon: 'ic_stat_smarttoko',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() => _ready ??= () async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Zona tidak dikenali: pakai WIB, zona sebagian besar pengguna.
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_smarttoko'),
        // Izin diminta saat pengguna menyalakan pengingat, bukan saat start.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _taps.add(payload);
      },
    );
  }();

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async {
    await _init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      case TargetPlatform.iOS:
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            ) ??
            false;
      default:
        return false;
    }
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async {
    await _init();
    await _plugin.cancelAllPendingNotifications();
    for (final n in plan) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        payload: n.payload,
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: _details,
        // Tidak butuh izin alarm presisi: mundur beberapa menit tidak
        // masalah untuk pengingat.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
