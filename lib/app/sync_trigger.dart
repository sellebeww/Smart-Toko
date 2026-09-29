/// Pemicu sinkronisasi.
///
/// Ini implementasi dari keputusan "tanpa layanan latar belakang": antrean
/// hanya diproses ketika aplikasi benar-benar dibuka pengguna, atau ketika
/// koneksi pulih sementara aplikasi sedang terbuka. Di luar itu aplikasi tidak
/// melakukan apa pun — dan itulah yang ingin bisa dikatakan dengan jujur kepada
/// pengguna yang khawatir aplikasinya "mengintai".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/transactions/transactions_providers.dart';
import 'providers.dart';

class SyncTrigger extends ConsumerStatefulWidget {
  final Widget child;

  const SyncTrigger({super.key, required this.child});

  @override
  ConsumerState<SyncTrigger> createState() => _SyncTriggerState();
}

class _SyncTriggerState extends ConsumerState<SyncTrigger>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  Future<void> _drain() async {
    final report = await ref.read(syncQueueProvider).drain();
    if (report.skipped || report.processed == 0) return;
    if (!mounted) return;
    ref.invalidate(pendingSyncCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityStatusProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      if (wasOffline && next.value == true) _drain();
    });

    return widget.child;
  }
}

final connectivityStatusProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectivityProvider).onStatusChange,
);
