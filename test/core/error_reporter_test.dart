/// Tes pelaporan error: yang dikirim, yang dibuang, dan batasnya.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/core/error_reporter.dart';

void main() {
  late List<Map<String, String>> sent;
  late bool signedIn;
  late bool enabled;
  late ErrorReporter reporter;

  setUp(() {
    sent = [];
    signedIn = true;
    enabled = true;
    reporter = ErrorReporter(
      send: (report) async => sent.add(report),
      isSignedIn: () => signedIn,
      isEnabled: () async => enabled,
      appVersion: '1.0.0+1',
      platform: 'android',
    );
  });

  test('mengirim jenis error, versi, dan platform', () async {
    final ok = await reporter.report(StateError('rusak'), StackTrace.current);

    expect(ok, isTrue);
    expect(sent.single['error_type'], contains('StateError'));
    expect(sent.single['message'], contains('rusak'));
    expect(sent.single['app_version'], '1.0.0+1');
    expect(sent.single['platform'], 'android');
  });

  test('membuang email dan angka panjang dari pesan', () async {
    await reporter.report(
      Exception('gagal untuk budi@contoh.com nominal 12500000 kode 123'),
      null,
    );

    final message = sent.single['message']!;
    expect(message, isNot(contains('budi@contoh.com')));
    expect(message, isNot(contains('12500000')));
    expect(message, contains('[email]'));
    expect(message, contains('kode 123'));
  });

  test('tidak mengirim saat belum masuk akun', () async {
    signedIn = false;

    expect(await reporter.report(StateError('x'), null), isFalse);
    expect(sent, isEmpty);
  });

  test('tidak mengirim bila sakelar laporan error mati', () async {
    enabled = false;

    expect(await reporter.report(StateError('x'), null), isFalse);
    expect(sent, isEmpty);
  });

  test('error yang sama hanya dilaporkan sekali per sesi', () async {
    await reporter.report(StateError('sama'), null);
    await reporter.report(StateError('sama'), null);

    expect(sent, hasLength(1));
  });

  test('dibatasi jumlah laporan per sesi', () async {
    for (var i = 0; i < 20; i++) {
      await reporter.report(StateError('beda $i'), null);
    }

    expect(sent, hasLength(ErrorReporter.maxReportsPerSession));
  });

  test('kegagalan pengiriman tidak melempar', () async {
    final failing = ErrorReporter(
      send: (_) async => throw Exception('offline'),
      isSignedIn: () => true,
      isEnabled: () async => true,
      appVersion: '1',
      platform: 'ios',
    );

    expect(await failing.report(StateError('x'), null), isFalse);
  });
}
