import '../features/sync/sync_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/dao/product_dao.dart';
import '../core/ui/figma_icon.dart';
import '../features/catalog/ui/catalog_screen.dart';
import '../features/reports/ui/report_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/transactions/ui/history_screen.dart';
import '../features/transactions/ui/home_screen.dart';
import '../features/voice_capture/capture_controller.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final capture = ref.watch(captureControllerProvider);
    final busy = capture is CaptureInProgress || capture is CaptureProcessing;
    // Karyawan tidak melihat laporan (laba, omzet periode, modal).
    final staff = ref.watch(isStaffProvider);
    final screens = [
      const HomeScreen(),
      const HistoryScreen(),
      const CatalogScreen(initialKind: ProductKind.bahan),
      if (!staff) const ReportScreen(),
      const SettingsScreen(),
    ];
    final index = _index.clamp(0, screens.length - 1);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: index, children: screens),
        bottomNavigationBar: SmartTokoNavigationBar(
          selectedIndex: index,
          enabled: !busy,
          showReports: !staff,
          onSelected: (index) => setState(() => _index = index),
        ),
      ),
    );
  }
}

class SmartTokoNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final bool enabled;
  final bool showReports;
  final ValueChanged<int> onSelected;
  const SmartTokoNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.enabled = true,
    this.showReports = true,
  });
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: enabled ? onSelected : null,
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFE8F2E9),
    height: 72,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected)
            ? const Color(0xFF176448)
            : const Color(0xFF718077),
      ),
    ),
    destinations: [
      NavigationDestination(
        enabled: enabled,
        icon: const FigmaIcon('06b62'),
        selectedIcon: const FigmaIcon('0bda6'),
        label: 'Beranda',
      ),
      NavigationDestination(
        enabled: enabled,
        icon: const FigmaIcon('3c63b'),
        selectedIcon: const FigmaIcon('b408a'),
        label: 'Transaksi',
      ),
      NavigationDestination(
        enabled: enabled,
        icon: const FigmaIcon('2b8e1'),
        selectedIcon: const FigmaIcon('a44c3'),
        label: 'Stok',
      ),
      if (showReports)
        NavigationDestination(
          enabled: enabled,
          icon: const FigmaIcon('a029f'),
          selectedIcon: const FigmaIcon('75d8a'),
          label: 'Laporan',
        ),
      NavigationDestination(
        enabled: enabled,
        icon: const FigmaIcon('e5ad6'),
        selectedIcon: const FigmaIcon('bae03'),
        label: 'Lainnya',
      ),
    ],
  );
}
