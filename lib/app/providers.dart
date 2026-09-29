/// Perakitan dependensi aplikasi.
///
/// Riverpod dipilih terutama karena banyak bagian aplikasi ini hidup di luar
/// widget tree — callback STT, pekerja antrean, pemantau koneksi — dan semuanya
/// butuh akses dependensi tanpa BuildContext.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/connectivity/connectivity_service.dart';
import '../core/db/app_database.dart';
import '../core/db/dao/contact_dao.dart';
import '../core/db/dao/parse_failure_dao.dart';
import '../core/db/dao/product_dao.dart';
import '../core/db/dao/settings_dao.dart';
import '../core/db/dao/store_dao.dart';
import '../core/secure/secure_key_store.dart';
import '../core/sync/remote_target.dart';
import '../core/sync/sync_queue.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/auth_providers.dart';
import '../features/stores/data/store_repository.dart';
import '../features/transactions/data/transaction_repository.dart';
import '../features/verification/data/verification_repository.dart';
import '../features/voice_capture/engines/speech_to_text_service.dart';
import '../features/voice_capture/speech_service.dart';
import '../features/voice_parser/llm/claude_llm_parser.dart';
import '../features/voice_parser/llm/llm_parser.dart';
import '../features/voice_parser/logging/parse_failure_logger.dart';
import '../features/voice_parser/parser_pipeline.dart';

/// Diisi di main() setelah basis data terbuka.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider harus di-override'),
);

/// Toko yang sedang aktif. Null berarti user belum (atau belum perlu)
/// memilih toko — diisi lewat gerbang toko di app/app.dart setelah user
/// login dan punya/memilih toko, bukan di-override sekali saat boot seperti
/// sebelumnya, karena satu akun sekarang bisa punya banyak toko.
class ActiveStoreId extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authStateChangesProvider.select((value) => value.value?.uid));
    return null;
  }

  /// Pilihan terakhir juga diingat di perangkat (lihat
  /// savedActiveStoreIdProvider) supaya pemilik beberapa toko tidak harus
  /// memilih ulang tiap membuka aplikasi. null (saat keluar akun) tidak
  /// menghapus ingatan itu — gerbang toko toh mengabaikan id yang bukan milik
  /// akun yang sedang login.
  Future<void> set(String? id) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (id != null && uid != null) {
      await ref
          .read(settingsDaoProvider)
          .setString('${SettingsKeys.activeStoreId}:$uid', id);
    }
    if (ref.mounted && ref.read(authStateChangesProvider).value?.uid == uid) {
      state = id;
    }
  }
}

final activeStoreIdProvider = NotifierProvider<ActiveStoreId, String?>(
  ActiveStoreId.new,
);

final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(appDatabaseProvider).db),
);

final storeDaoProvider = Provider<StoreDao>(
  (ref) => StoreDao(ref.watch(appDatabaseProvider).db),
);

final productDaoProvider = Provider<ProductDao>(
  (ref) => ProductDao(ref.watch(appDatabaseProvider).db),
);

final contactDaoProvider = Provider<ContactDao>(
  (ref) => ContactDao(ref.watch(appDatabaseProvider).db),
);

/// Naik setiap ada penulisan data operasional (transaksi, produk, stok,
/// kontak). Provider baca yang menontonnya ikut dimuat ulang, jadi layar yang
/// menulis tidak perlu tahu layar lain mana saja yang harus disegarkan.
class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataRevisionProvider = NotifierProvider<DataRevision, int>(
  DataRevision.new,
);

final connectivityProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityPlusService(),
);

final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// Satu client menyediakan Auth, Postgres (lewat `.from(...)`), dan Storage.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(supabaseClientProvider)),
);

final verificationRepositoryProvider = Provider<VerificationRepository>(
  (ref) => VerificationRepository(ref.watch(supabaseClientProvider)),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final parseFailureLoggerProvider = Provider<ParseFailureLogger>(
  (ref) => ParseFailureDao(ref.watch(appDatabaseProvider).db),
);

final llmParserProvider = Provider<LlmParser>((ref) {
  final settings = ref.watch(settingsDaoProvider);
  final keyStore = ref.watch(keyStoreProvider);

  return GatedLlmParser(
    isEnabled: () async =>
        await settings.llmEnabled() && await keyStore.hasLlmApiKey(),
    disabledReason: 'Bantuan AI mati atau kunci API belum diisi',
    delegate: ClaudeLlmParser(
      apiKeyProvider: keyStore.readLlmApiKey,
      httpClient: ref.watch(httpClientProvider),
    ),
  );
});

final parserPipelineProvider = Provider<ParserPipeline>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return ParserPipeline(
    llmParser: ref.watch(llmParserProvider),
    failureLogger: ref.watch(parseFailureLoggerProvider),
    isOnline: connectivity.isOnline,
  );
});

final speechServiceProvider = Provider<SpeechService>(
  (ref) => SpeechToTextService(connectivity: ref.watch(connectivityProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(database: ref.watch(appDatabaseProvider)),
);

final remoteSyncTargetProvider = Provider<RemoteSyncTarget>(
  // Target simulasi hanya untuk pengujian, tidak boleh mengakui kiriman nyata.
  (ref) => const UnconfiguredRemoteSyncTarget(),
);

final syncQueueProvider = Provider<SyncQueue>(
  (ref) => SyncQueue(
    database: ref.watch(appDatabaseProvider),
    target: ref.watch(remoteSyncTargetProvider),
  ),
);
