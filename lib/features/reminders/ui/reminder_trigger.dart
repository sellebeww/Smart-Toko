/// Menyelaraskan jadwal pengingat dengan data toko, dan membuka layar yang
/// tepat saat notifikasi diketuk.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../debts/ui/debts_screen.dart';
import '../notification_scheduler.dart';
import '../reminder_providers.dart';

class ReminderTrigger extends ConsumerStatefulWidget {
  final Widget child;
  const ReminderTrigger({super.key, required this.child});

  @override
  ConsumerState<ReminderTrigger> createState() => _ReminderTriggerState();
}

class _ReminderTriggerState extends ConsumerState<ReminderTrigger>
    with WidgetsBindingObserver {
  late final NotificationScheduler _scheduler;
  StreamSubscription<String>? _taps;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scheduler = ref.read(notificationSchedulerProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _sync();
      _taps = _scheduler.taps.listen(_open);
      try {
        _open(await _scheduler.launchPayload());
      } catch (_) {
        // Tanpa plugin (mis. tes) tidak ada yang perlu dibuka.
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _taps?.cancel();
    // Keluar akun atau ganti toko: jadwal lama tidak boleh tetap berbunyi.
    // Toko berikutnya menjadwalkan ulang sendiri saat dibuka.
    unawaited(_scheduler.replaceAll(const []).catchError((_) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hari bisa berganti selama aplikasi di latar.
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _sync);
  }

  Future<void> _sync() async {
    if (!mounted) return;
    try {
      await ref.read(reminderSyncProvider)();
    } catch (_) {
      // Pengingat bersifat bantuan: kegagalannya tidak boleh mengganggu
      // pencatatan. Dicoba lagi pada perubahan berikutnya.
    }
  }

  void _open(String? payload) {
    if (!mounted || payload != 'debts') return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DebtsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataRevisionProvider, (_, _) => _scheduleSync());
    ref.listen(activeStoreIdProvider, (_, _) => _scheduleSync());
    ref.listen(reminderSettingsProvider, (_, _) => _scheduleSync());
    return widget.child;
  }
}
