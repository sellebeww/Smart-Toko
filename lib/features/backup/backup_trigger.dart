/// Pemicu cadangan otomatis.
///
/// Tidak ada layanan latar belakang: cadangan hanya dicoba saat aplikasi
/// dibuka, saat koneksi pulih sementara aplikasi terbuka, dan sesaat ketika
/// aplikasi ditinggalkan — supaya catatan terakhir ikut tercadang. Semuanya
/// hanya bila pengguna menyalakan pencadangan di Pengaturan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../auth/auth_providers.dart';
import 'backup_providers.dart';

class BackupTrigger extends ConsumerStatefulWidget {
  final Widget child;

  const BackupTrigger({super.key, required this.child});

  @override
  ConsumerState<BackupTrigger> createState() => _BackupTriggerState();
}

class _BackupTriggerState extends ConsumerState<BackupTrigger>
    with WidgetsBindingObserver {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _backup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backup();
      case AppLifecycleState.paused:
        _backup(force: true);
      default:
        break;
    }
  }

  Future<void> _backup({bool force = false}) async {
    if (_running) return;
    final uid = ref.read(authStateChangesProvider).value?.uid;
    final storeId = ref.read(activeStoreIdProvider);
    if (uid == null || storeId == null) return;
    _running = true;
    try {
      final uploaded = await ref
          .read(backupServiceProvider)
          .backupIfNeeded(ownerUid: uid, storeId: storeId, force: force);
      if (uploaded && mounted) ref.invalidate(backupStatusProvider);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityStatusProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      if (wasOffline && next.value == true) _backup();
    });

    return widget.child;
  }
}
