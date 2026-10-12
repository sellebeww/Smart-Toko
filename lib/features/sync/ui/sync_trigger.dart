/// Pemicu sinkronisasi otomatis untuk toko aktif: saat dibuka, kembali dari
/// latar, koneksi pulih, data berubah, dan berkala selama aplikasi terbuka.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../stores/stores_providers.dart';
import '../sync_providers.dart';
import '../sync_remote.dart';

class SyncTrigger extends ConsumerStatefulWidget {
  final Widget child;
  const SyncTrigger({super.key, required this.child});

  @override
  ConsumerState<SyncTrigger> createState() => _SyncTriggerState();
}

class _SyncTriggerState extends ConsumerState<SyncTrigger>
    with WidgetsBindingObserver {
  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;

  /// Revisi data yang kita sendiri naikkan setelah menerapkan data server;
  /// tidak perlu memicu sinkron lagi.
  int? _ownBump;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    _startPeriodic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }

  void _startPeriodic() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(seconds: 30), (_) => _sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startPeriodic();
        _sync();
      case AppLifecycleState.paused:
        _periodic?.cancel();
        // Catatan terakhir sempat terkirim sebelum aplikasi ditinggal.
        _sync();
      default:
        break;
    }
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _sync);
  }

  Future<void> _sync() async {
    if (_running || !mounted) return;
    final store = ref.read(activeStoreProvider).value;
    if (store == null) return;
    final engine = ref.read(syncEngineProvider);
    _running = true;
    try {
      final enabledHere = await engine.isEnabled(store.id);
      if (!store.syncEnabled) {
        // Dimatikan pemilik dari HP lain: berhenti mencatat antrean.
        if (enabledHere) await engine.disableLocal(store.id);
        return;
      }
      final result = enabledHere
          ? await engine.sync(store.id)
          : await engine.enable(store.id, firstDevice: false);
      ref.read(syncErrorProvider.notifier).set(null);
      if (result.changedLocalData && mounted) {
        final revision = ref.read(dataRevisionProvider.notifier);
        revision.bump();
        _ownBump = ref.read(dataRevisionProvider);
      }
    } on SyncAccessLost {
      await _accessLost(store.id, store.name);
    } catch (_) {
      if (mounted) {
        ref
            .read(syncErrorProvider.notifier)
            .set('Belum tersinkron. Akan dicoba lagi saat online.');
      }
    } finally {
      _running = false;
    }
  }

  /// Karyawan dikeluarkan, atau pemilik mematikan sinkronisasi: salinan
  /// toko di HP karyawan dihapus. Pemilik tidak pernah kehilangan akses ke
  /// tokonya sendiri, jadi bagian ini hanya mengenai karyawan.
  Future<void> _accessLost(String storeId, String storeName) async {
    final store = ref.read(activeStoreProvider).value;
    if (store == null || store.isOwnedBy(_uid)) return;
    await ref.read(syncEngineProvider).removeLocalStore(storeId);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Akses ke $storeName sudah dicabut pemiliknya.')),
    );
    await ref.read(activeStoreIdProvider.notifier).set(null);
    ref.invalidate(userStoresProvider);
  }

  String? get _uid => ref.read(supabaseClientProvider).auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    ref.listen(dataRevisionProvider, (_, next) {
      if (next == _ownBump) return;
      _soon();
    });
    ref.listen(activeStoreProvider, (previous, next) {
      final was = previous?.value;
      final now = next.value;
      if (now != null &&
          (was?.id != now.id || was?.syncEnabled != now.syncEnabled)) {
        _sync();
      }
    });
    ref.listen(connectivityStatusProvider, (previous, next) {
      if (previous?.value == false && next.value == true) _sync();
    });
    return widget.child;
  }
}
