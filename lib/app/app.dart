/// Kerangka aplikasi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/stores/domain/store_profile.dart';
import '../features/stores/stores_providers.dart';
import '../features/stores/ui/add_store_screen.dart';
import '../features/stores/ui/store_list_screen.dart';
import '../features/transactions/ui/home_screen.dart';
import '../features/voice_capture/capture_controller.dart';
import 'providers.dart';
import 'sync_trigger.dart';

class SmartTokoApp extends ConsumerStatefulWidget {
  final bool onboardingDone;

  const SmartTokoApp({super.key, required this.onboardingDone});

  @override
  ConsumerState<SmartTokoApp> createState() => _SmartTokoAppState();
}

class _SmartTokoAppState extends ConsumerState<SmartTokoApp> {
  late bool _onboardingDone = widget.onboardingDone;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateChangesProvider);
    ref.listen(authStateChangesProvider, (previous, next) {
      if (previous?.value?.uid != next.value?.uid) {
        ref.invalidate(captureControllerProvider);
      }
    });

    return MaterialApp(
      // Ganti akun (login/keluar) = tumpukan layar baru. Tanpa ini, layar yang
      // di-push (mis. Pengaturan) tetap menutupi gerbang login setelah keluar.
      key: ValueKey(authState.value?.uid),
      title: 'SmartToko',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: authState.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Gagal memuat status akun: $error'),
            ),
          ),
        ),
        data: (user) {
          if (user == null) return const LoginScreen();
          return _StoreGate(
            onboardingDone: _onboardingDone,
            onOnboardingDone: () => setState(() => _onboardingDone = true),
          );
        },
      ),
    );
  }
}

/// Gerbang kedua (setelah auth): pastikan user punya toko aktif sebelum
/// masuk ke onboarding/home. Belum punya toko sama sekali -> wajib isi
/// AddStoreScreen dulu. Punya toko tapi belum ada yang aktif -> StoreListScreen.
class _StoreGate extends ConsumerWidget {
  final bool onboardingDone;
  final VoidCallback onOnboardingDone;

  const _StoreGate({
    required this.onboardingDone,
    required this.onOnboardingDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(userStoresProvider);
    final activeStoreId = ref.watch(activeStoreIdProvider);

    return storesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Gagal memuat toko: $error'),
          ),
        ),
      ),
      data: (stores) {
        if (stores.isEmpty) return const AddStoreScreen();

        StoreProfile? active;
        for (final s in stores) {
          if (s.id == activeStoreId) {
            active = s;
            break;
          }
        }
        if (active == null) return const StoreListScreen();

        return onboardingDone
            ? const SyncTrigger(child: HomeScreen())
            : OnboardingScreen(onDone: onOnboardingDone);
      },
    );
  }
}
