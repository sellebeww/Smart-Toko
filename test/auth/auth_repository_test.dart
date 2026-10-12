/// Tes AuthRepository terhadap permintaan HTTP sungguhan SDK Supabase Auth.
///
/// Yang dijaga: daftar tanpa sesi dikenali sebagai "perlu konfirmasi email",
/// kata sandi salah dan kode OTP salah ditolak, dan reset kata sandi baru
/// mengganti kata sandi setelah kodenya terverifikasi.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_toko/features/auth/data/auth_repository.dart';
import 'package:smart_toko/features/auth/domain/app_user.dart';

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

final String _accessToken =
    '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
    '${_b64({'sub': 'u1', 'role': 'authenticated', 'exp': 4102444800})}.sig';

Map<String, Object?> _user() => {
  'id': 'u1',
  'aud': 'authenticated',
  'email': 'budi@contoh.com',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
  'created_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> _session() => {
  'access_token': _accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': _user(),
};

/// Penyimpanan PKCE di memori; SDK mewajibkannya untuk alur daftar.
class _MemoryStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> removeItem({required String key}) async => _values.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _values[key] = value;
}

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request request) respond;
  late AuthRepository repository;

  http.Response reply(http.Request request, Object? body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  setUp(() {
    requests = [];
    respond = (request) => reply(request, {'msg': 'tak terduga'}, 404);
    final client = SupabaseClient(
      'https://contoh.supabase.co',
      'sb_publishable_tes',
      authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStorage()),
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    repository = AuthRepository(client);
  });

  group('daftar', () {
    test('tanpa sesi berarti email perlu dikonfirmasi', () async {
      respond = (request) => reply(request, _user());

      await expectLater(
        repository.signUp(email: 'budi@contoh.com', password: 'rahasia123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'email_confirmation_required',
          ),
        ),
      );
    });

    test('dengan sesi langsung mengembalikan pengguna', () async {
      respond = (request) => reply(request, _session());

      final user = await repository.signUp(
        email: 'budi@contoh.com',
        password: 'rahasia123',
      );

      expect(user.uid, 'u1');
      expect(user.email, 'budi@contoh.com');
    });
  });

  group('masuk', () {
    test('berhasil mengembalikan pengguna', () async {
      respond = (request) => reply(request, _session());

      final user = await repository.signIn(
        email: 'budi@contoh.com',
        password: 'rahasia123',
      );

      expect(user.uid, 'u1');
      expect(repository.currentUser?.uid, 'u1');
    });

    test('kata sandi salah ditolak', () async {
      respond = (request) => reply(request, {
        'error_code': 'invalid_credentials',
        'msg': 'Invalid login credentials',
      }, 400);

      await expectLater(
        repository.signIn(email: 'budi@contoh.com', password: 'salah'),
        throwsA(isA<AuthException>()),
      );
      expect(repository.currentUser, isNull);
    });

    test('keluar membersihkan sesi', () async {
      respond = (request) => request.url.path.endsWith('/logout')
          ? http.Response('', 204, request: request)
          : reply(request, _session());
      await repository.signIn(email: 'budi@contoh.com', password: 'rahasia123');

      await repository.signOut();

      expect(repository.currentUser, isNull);
    });
  });

  group('reset kata sandi dengan kode', () {
    test('kode benar memverifikasi lalu mengganti kata sandi', () async {
      respond = (request) {
        if (request.url.path.endsWith('/verify')) {
          return reply(request, _session());
        }
        if (request.url.path.endsWith('/user') && request.method == 'PUT') {
          return reply(request, _user());
        }
        return reply(request, {'msg': 'tak terduga'}, 404);
      };

      await repository.resetPasswordWithCode(
        email: ' budi@contoh.com ',
        code: ' 123456 ',
        newPassword: 'baruBaru123',
      );

      final verify = requests.firstWhere((r) => r.url.path.endsWith('/verify'));
      final verifyBody = jsonDecode(verify.body) as Map<String, Object?>;
      expect(verifyBody['type'], 'recovery');
      expect(verifyBody['token'], '123456');
      expect(verifyBody['email'], 'budi@contoh.com');

      final update = requests.last;
      expect(update.method, 'PUT');
      expect(jsonDecode(update.body)['password'], 'baruBaru123');
    });

    test('kode salah ditolak dan kata sandi tidak diganti', () async {
      respond = (request) => reply(request, {
        'error_code': 'otp_expired',
        'msg': 'Token has expired or is invalid',
      }, 403);

      await expectLater(
        repository.resetPasswordWithCode(
          email: 'budi@contoh.com',
          code: '000000',
          newPassword: 'baruBaru123',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    });
  });

  group('konfirmasi pendaftaran', () {
    test('kode dikirim sebagai tipe email', () async {
      respond = (request) => reply(request, _session());

      await repository.verifySignupCode(
        email: 'budi@contoh.com',
        code: '654321',
      );

      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body['type'], 'email');
      expect(body['token'], '654321');
    });

    test('kode salah ditolak', () async {
      respond = (request) => reply(request, {
        'error_code': 'otp_expired',
        'msg': 'Token has expired or is invalid',
      }, 403);

      await expectLater(
        repository.verifySignupCode(email: 'budi@contoh.com', code: '111111'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('masuk dengan nomor HP', () {
    test('kode SMS dikirim ke nomor berformat internasional', () async {
      respond = (request) => reply(request, <String, Object?>{});

      await repository.sendPhoneCode('628123456789');

      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(requests.single.url.path, endsWith('/otp'));
      expect(body['phone'], '+628123456789');
    });

    test('kode benar membuat sesi dan identitasnya nomor HP', () async {
      respond = (request) => reply(request, {
        ..._session(),
        'user': {..._user(), 'email': null, 'phone': '628123456789'},
      });

      final user = await repository.verifyPhoneCode(
        phone: '628123456789',
        code: ' 123456 ',
      );

      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body['type'], 'sms');
      expect(body['token'], '123456');
      expect(body['phone'], '+628123456789');
      expect(user.identity, '+628123456789');
    });

    test('kode salah ditolak', () async {
      respond = (request) => reply(request, {
        'error_code': 'otp_expired',
        'msg': 'Token has expired or is invalid',
      }, 403);

      await expectLater(
        repository.verifyPhoneCode(phone: '628123456789', code: '000000'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  test('identitas memakai email bila ada', () {
    expect(
      const AppUser(uid: 'u', email: 'a@b.com', phone: '62812').identity,
      'a@b.com',
    );
    expect(const AppUser(uid: 'u').identity, isNull);
  });
}
