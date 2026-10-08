/// Pelaporan error tak tertangani ke server SmartToko sendiri.
///
/// Hanya aktif bila pengguna menyalakan sakelarnya di Pengaturan (bawaannya
/// mati, seperti semua pengiriman data lain di aplikasi ini).
///
/// Sengaja tidak memakai layanan pihak ketiga: laporan hanya berisi jenis
/// error, pesan dan stack yang dipotong, versi aplikasi, dan platform. Email
/// dan angka panjang (nomor HP, nominal, NIK) dibuang dari teks sebelum
/// dikirim, karena pesan exception kadang ikut memuat isi input pengguna.
///
/// Pelaporan bersifat upaya terbaik: tidak pernah melempar, tidak menahan
/// aplikasi, dan dibatasi per sesi supaya satu bug yang berulang tidak
/// membanjiri server.
library;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ErrorSender = Future<void> Function(Map<String, String> report);

class ErrorReporter {
  static const int maxReportsPerSession = 5;

  final ErrorSender _send;
  final bool Function() _isSignedIn;
  final Future<bool> Function() _isEnabled;
  final String appVersion;
  final String platform;

  final Set<String> _seen = {};
  int _sent = 0;

  ErrorReporter({
    required this._send,
    required this._isSignedIn,
    required this._isEnabled,
    required this.appVersion,
    required this.platform,
  });

  /// Pelaporan dengan Supabase sebagai tujuan.
  static Future<ErrorReporter> forSupabase(
    SupabaseClient client, {
    required Future<bool> Function() isEnabled,
  }) async {
    var version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Versi hanya pelengkap laporan.
    }
    return ErrorReporter(
      send: (report) => client.rpc(
        'report_client_error',
        params: {
          'p_app_version': report['app_version'],
          'p_platform': report['platform'],
          'p_error_type': report['error_type'],
          'p_message': report['message'],
          'p_stack': report['stack'],
        },
      ),
      isSignedIn: () => client.auth.currentSession != null,
      isEnabled: isEnabled,
      appVersion: version,
      platform: defaultTargetPlatform.name,
    );
  }

  /// Memasang penangkap error Flutter dan error asinkron. Penangan bawaan
  /// Flutter tetap dipanggil, jadi perilaku saat debugging tidak berubah.
  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      report(details.exception, details.stack);
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Mengembalikan true bila laporan benar-benar dikirim.
  Future<bool> report(Object error, StackTrace? stack) async {
    try {
      if (_sent >= maxReportsPerSession || !_isSignedIn()) return false;
      if (!await _isEnabled()) return false;

      final type = error.runtimeType.toString();
      final message = scrub(error.toString());
      final trace = scrub(stack?.toString() ?? '');
      // Error yang sama berulang cukup dilaporkan sekali per sesi.
      final signature = '$type|${message.split('\n').first}';
      if (!_seen.add(signature)) return false;

      _sent++;
      await _send({
        'app_version': appVersion,
        'platform': platform,
        'error_type': type,
        'message': message,
        'stack': trace,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final RegExp _longNumber = RegExp(r'\d{6,}');

  /// Membuang email dan angka panjang dari teks laporan.
  @visibleForTesting
  static String scrub(String text) =>
      text.replaceAll(_email, '[email]').replaceAll(_longNumber, '[angka]');
}
