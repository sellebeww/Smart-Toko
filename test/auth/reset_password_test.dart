import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/features/auth/data/auth_repository.dart';
import 'package:smart_toko/features/auth/ui/reset_password_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeGoTrueClient extends Fake implements GoTrueClient {
  final requests = <String>[];
  final verified = <(String, String)>[];
  final passwords = <String>[];
  Completer<void>? pending;
  String? errorCode;
  String? verifyErrorCode;

  @override
  Future<AuthResponse> verifyOTP({
    String? email,
    String? phone,
    String? token,
    required OtpType type,
    String? redirectTo,
    String? captchaToken,
    String? tokenHash,
  }) async {
    expect(type, OtpType.recovery);
    final code = verifyErrorCode;
    if (code != null) {
      throw AuthException('fake', statusCode: '403', code: code);
    }
    verified.add((email!, token!));
    return AuthResponse();
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    passwords.add(attributes.password!);
    return UserResponse.fromJson({'id': 'u1'});
  }

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    requests.add(email);
    final code = errorCode;
    if (code != null) {
      // statusCode null mensimulasikan kegagalan jaringan (tidak sempat
      // dibalas server) — lihat pemetaan pesan di ResetPasswordScreen.
      throw AuthException(
        'fake error',
        statusCode: code == 'network' ? null : '400',
        code: code == 'network' ? null : code,
      );
    }
    await pending?.future;
  }
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  FakeSupabaseClient(this._auth);
  final GoTrueClient _auth;

  @override
  GoTrueClient get auth => _auth;
}

void main() {
  late FakeGoTrueClient auth;
  setUp(() => auth = FakeGoTrueClient());

  Future<void> pump(WidgetTester tester, {String email = ''}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            AuthRepository(FakeSupabaseClient(auth)),
          ),
        ],
        child: MaterialApp(home: ResetPasswordScreen(initialEmail: email)),
      ),
    );
  }

  testWidgets('invalid email never contacts Supabase', (tester) async {
    await pump(tester, email: 'bukan-email');
    await tester.tap(find.text('Kirim kode'));
    await tester.pump();
    expect(auth.requests, isEmpty);
    expect(find.text('Masukkan email yang valid'), findsOneWidget);
  });

  testWidgets('trims email and shows success', (tester) async {
    await pump(tester, email: ' toko@example.com ');
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();
    expect(auth.requests, ['toko@example.com']);
    expect(find.textContaining('Periksa kotak masuk'), findsOneWidget);
  });

  testWidgets('code and new password are verified then saved', (tester) async {
    await pump(tester, email: 'toko@example.com');
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kode dari email'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi baru'),
      'rahasia123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ulangi kata sandi baru'),
      'rahasia123',
    );
    await tester.tap(find.text('Simpan kata sandi baru'));
    await tester.pumpAndSettle();

    expect(auth.verified, [('toko@example.com', '123456')]);
    expect(auth.passwords, ['rahasia123']);
  });

  testWidgets('expired code shows a clear message and keeps the form', (
    tester,
  ) async {
    auth.verifyErrorCode = 'otp_expired';
    await pump(tester, email: 'toko@example.com');
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kode dari email'),
      '000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi baru'),
      'rahasia123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ulangi kata sandi baru'),
      'rahasia123',
    );
    await tester.tap(find.text('Simpan kata sandi baru'));
    await tester.pumpAndSettle();

    expect(find.textContaining('kedaluwarsa'), findsOneWidget);
    expect(auth.passwords, isEmpty);
    expect(find.text('Simpan kata sandi baru'), findsOneWidget);
  });

  testWidgets('short or mismatched password never reaches Supabase', (
    tester,
  ) async {
    await pump(tester, email: 'toko@example.com');
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kode dari email'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi baru'),
      'pendek',
    );
    await tester.tap(find.text('Simpan kata sandi baru'));
    await tester.pumpAndSettle();

    expect(find.text('Minimal 8 karakter'), findsOneWidget);
    expect(auth.verified, isEmpty);
  });

  testWidgets('network error keeps form available for retry', (tester) async {
    auth.errorCode = 'network';
    await pump(tester, email: 'toko@example.com');
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();
    expect(
      find.text('Periksa koneksi internet, lalu coba lagi.'),
      findsOneWidget,
    );
    auth.errorCode = null;
    await tester.tap(find.text('Kirim kode'));
    await tester.pumpAndSettle();
    expect(auth.requests.length, 2);
    expect(find.textContaining('Periksa kotak masuk'), findsOneWidget);
  });

  testWidgets(
    'unknown account still gets a success message (Supabase tidak membocorkan keberadaan email)',
    (tester) async {
      // Tidak ada errorCode yang di-set — resetPasswordForEmail Supabase
      // sukses tanpa error baik email itu terdaftar atau tidak.
      await pump(tester, email: 'tidak-terdaftar@example.com');
      await tester.tap(find.text('Kirim kode'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Periksa kotak masuk'), findsOneWidget);
    },
  );

  testWidgets('leaving while request runs does not update a disposed screen', (
    tester,
  ) async {
    auth.pending = Completer<void>();
    await pump(tester, email: 'toko@example.com');
    await tester.tap(find.text('Kirim kode'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
