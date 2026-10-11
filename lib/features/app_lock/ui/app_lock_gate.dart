/// Gerbang kunci: menutupi seluruh aplikasi (termasuk layar yang sedang
/// dibuka) saat terkunci, dan menutup tampilan saat aplikasi di latar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../app_lock_controller.dart';
import '../pin_hasher.dart';
import 'pin_dialogs.dart';

/// Lama aplikasi boleh ditinggalkan sebelum terkunci lagi. Cukup panjang
/// agar izin mikrofon/kamera dan berpindah sebentar ke WhatsApp tidak
/// memaksa memasukkan PIN berulang.
const Duration lockGracePeriod = Duration(seconds: 60);

class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _leftAt;
  bool _inBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final now = ref.read(appLockClockProvider)();
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null && now.difference(left) >= lockGracePeriod) {
          ref.read(appLockControllerProvider.notifier).lock();
        }
        setState(() => _inBackground = false);
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _leftAt ??= now;
        setState(() => _inBackground = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appLockControllerProvider);
    final lock = async.value;
    final enabled = lock?.enabled ?? false;
    final locked = lock?.locked ?? false;
    // Status kunci belum terbaca (beberapa milidetik saat aplikasi dibuka):
    // isi aplikasi tidak boleh sempat terlihat.
    final loading = async.isLoading && !async.hasValue;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (loading)
          const Positioned.fill(child: ColoredBox(color: SmartTokoTheme.canvas))
        else if (locked)
          const Positioned.fill(child: LockScreen())
        else if (enabled && _inBackground)
          // Isi aplikasi tidak boleh terlihat di pratinjau aplikasi terbuka.
          const Positioned.fill(
            child: ColoredBox(color: SmartTokoTheme.canvas),
          ),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final TextEditingController _pin = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Sekali tiap terkunci. Bila dibatalkan, tombolnya tetap ada; dialog
    // tidak dipaksakan berulang.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(appLockControllerProvider).value?.biometric ?? false) {
        _biometric();
      }
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _biometric() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ref
        .read(appLockControllerProvider.notifier)
        .unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) _error = null;
    });
  }

  Future<void> _submit() async {
    if (_checking || !isValidPin(_pin.text)) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .unlock(_pin.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _pin.clear();
      _error = switch (result) {
        UnlockResult.success => null,
        UnlockResult.wrong => 'PIN salah.',
        UnlockResult.blocked => _blockedMessage(),
      };
    });
  }

  String _blockedMessage() => blockedText(
    ref.read(appLockControllerProvider).value?.blockedUntil,
    ref.read(appLockClockProvider)(),
  );

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lupa PIN?'),
        content: const Text(
          'Kamu akan keluar dari akun dan kunci PIN dihapus. Masuk lagi '
          'dengan email dan kata sandi untuk membuka datamu. Data tetap '
          'aman di HP ini dan di cadangan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(appLockControllerProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: SmartTokoTheme.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text('SmartToko terkunci', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Masukkan PIN untuk membuka.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: maxPinLength,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: theme.textTheme.headlineSmall?.copyWith(
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'PIN',
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    onChanged: (value) {
                      setState(() {});
                      // PIN umumnya 4 angka: coba otomatis di panjang itu
                      // dan di panjang maksimum.
                      if (value.length == maxPinLength) _submit();
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _checking || !isValidPin(_pin.text)
                          ? null
                          : _submit,
                      child: const Text('Buka'),
                    ),
                  ),
                  if (ref.watch(appLockControllerProvider).value?.biometric ??
                      false)
                    TextButton.icon(
                      onPressed: _checking ? null : _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Pakai sidik jari / wajah'),
                    ),
                  TextButton(
                    onPressed: _forgot,
                    child: const Text('Lupa PIN? Keluar dari akun'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
