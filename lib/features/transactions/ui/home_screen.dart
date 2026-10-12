/// Layar utama: satu tombol besar untuk mencatat.
///
/// Tata letaknya tunduk pada satu kasus pemakaian: tangan sibuk atau kotor.
/// Karena itu tombol rekam dibuat sangat besar dan berada di jangkauan ibu
/// jari, dan tombol "ketik manual" duduk tepat di sebelahnya dengan bobot yang
/// setara — bukan disembunyikan di menu.
library;

import '../../sync/sync_providers.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/ui/brand.dart';
import '../../../core/ui/figma_icon.dart';
import '../../../core/db/dao/product_dao.dart';
import '../../catalog/catalog_providers.dart';
import '../../reports/domain/insights.dart';
import '../../reports/recording_progress.dart';
import 'text_entry_sheet.dart';
import '../../../core/format.dart';
import '../../backup/backup_actions.dart';
import '../../backup/backup_providers.dart';
import '../../settings/ui/settings_screen.dart';
import '../../stores/stores_providers.dart';
import '../../stores/ui/store_list_screen.dart';
import '../../verification/domain/verification_status.dart';
import '../../voice_capture/capture_controller.dart';
import '../../voice_capture/speech_service.dart';
import '../../catalog/ui/catalog_screen.dart';
import '../../debts/debts_providers.dart';
import '../../debts/ui/debts_screen.dart';
import '../../reminders/ui/reminder_settings_tiles.dart';
import '../../contacts/contacts_providers.dart';
import '../../contacts/ui/contacts_screen.dart';
import '../../reports/reports_providers.dart';
import '../domain/transaction_draft.dart';
import '../transactions_providers.dart';
import '../history_providers.dart';
import 'history_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_editor.dart';
import 'transaction_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _sheetOpen = false;
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh();
  }

  void _scheduleDayRefresh() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    _dayTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        _refresh();
        _scheduleDayRefresh();
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(todayTransactionsProvider);
    ref.invalidate(todayTotalsProvider);
    ref.invalidate(historyTransactionsProvider);
    ref.invalidate(dailyMotivationProvider);
    ref.invalidate(reportProvider);
    ref.invalidate(recordingDaysProvider);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _scheduleDayRefresh();
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openSheet(TransactionDraft draft) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showTransactionEditor(context, ref, draft: draft);
    } finally {
      _sheetOpen = false;
      if (mounted) ref.read(captureControllerProvider.notifier).reset();
    }
  }

  void _handleCaptureState(CaptureState? previous, CaptureState next) {
    switch (next) {
      case CaptureReady(:final draft):
        _openSheet(draft);
      case CaptureUnavailable(:final reason):
        _offerManualEntry(reason);
      default:
        break;
    }
  }

  /// Saat suara gagal, pengguna TIDAK dibiarkan dengan pesan galat saja.
  /// Masukan manual langsung ditawarkan di tempat yang sama.
  Future<void> _offerManualEntry(VoiceUnavailableReason reason) async {
    if (_sheetOpen) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_reasonMessage(reason)),
        duration: const Duration(seconds: 5),
      ),
    );
    ref.read(captureControllerProvider.notifier).reset();
    await _openSheet(TransactionDraft.manual());
  }

  static String _reasonMessage(VoiceUnavailableReason reason) =>
      switch (reason) {
        VoiceUnavailableReason.permissionDenied =>
          'Izin mikrofon belum diberikan. Silakan ketik manual.',
        VoiceUnavailableReason.noSpeechEngine =>
          'Perangkat ini tidak punya pengenal suara. Silakan ketik manual.',
        VoiceUnavailableReason.languageModelMissing => 'Bahasa Indonesia belum tersedia untuk pengenalan suara. Silakan ketik manual.',
        VoiceUnavailableReason.offlineAndNoOnDeviceModel => 'Sedang luring dan pengenalan suara luring belum tersedia. Silakan ketik manual.',
        VoiceUnavailableReason.recognitionError =>
          'Pengenalan suara bermasalah. Silakan ketik manual.',
        VoiceUnavailableReason.noSpeechDetected =>
          'Tidak ada suara yang tertangkap. Silakan ketik manual.',
      };

  @override
  Widget build(BuildContext context) {
    ref.listen<CaptureState>(captureControllerProvider, _handleCaptureState);

    final captureState = ref.watch(captureControllerProvider);
    final totals = ref.watch(reportProvider(ReportPeriod.hariIni));
    final transactions = ref.watch(todayTransactionsProvider);
    final motivation = ref.watch(dailyMotivationProvider).value;
    final contactNames = ref.watch(contactNamesProvider).value ?? const {};
    final capturing =
        captureState is CaptureInProgress || captureState is CaptureProcessing;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Row(
          children: [
            const SmartTokoLogo(size: 46),
            const SizedBox(width: 8),
            Expanded(child: _StoreTitle(enabled: !capturing)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: capturing
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _TodaySummary(
                      totals: totals,
                      showProfit: !ref.watch(isStaffProvider),
                    ),
                  ),
                  const SliverToBoxAdapter(child: _RestoreOffer()),
                  SliverToBoxAdapter(
                    child: _CaptureBar(
                      state: captureState,
                      onStart: () =>
                          ref.read(captureControllerProvider.notifier).start(),
                      onStop: () =>
                          ref.read(captureControllerProvider.notifier).stop(),
                      onManual: () async {
                        await ref
                            .read(captureControllerProvider.notifier)
                            .cancel();
                        if (!context.mounted) return;
                        final draft = await showTextEntry(context);
                        if (draft != null && mounted) await _openSheet(draft);
                      },
                    ),
                  ),
                  SliverToBoxAdapter(child: _QuickAccess(enabled: !capturing)),
                  SliverToBoxAdapter(child: _DebtAlert(enabled: !capturing)),
                  const SliverToBoxAdapter(child: ReminderOfferCard()),
                  SliverToBoxAdapter(
                    child: _LowStockAlert(enabled: !capturing),
                  ),
                  const SliverToBoxAdapter(child: RecordingProgressCard()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Aktivitas terbaru',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: capturing
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const HistoryScreen(),
                                    ),
                                  ),
                            child: const Text('Lihat semua'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  transactions.when(
                    loading: () => const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    error: (error, _) => SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text('Catatan belum berhasil dimuat.'),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const SliverToBoxAdapter(child: _EmptyState())
                        : SliverList.builder(
                            itemCount: items.length > 3 ? 3 : items.length,
                            itemBuilder: (context, index) {
                              final r = items[index];
                              return TransactionTile(
                                record: r,
                                contactName: r.contactId == null
                                    ? null
                                    : contactNames[r.contactId],
                                onTap: capturing
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              TransactionDetailScreen(
                                                transactionId: r.id,
                                              ),
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                  if (motivation != null && motivation.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2E9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                FigmaIcon('85387'),
                                SizedBox(width: 8),
                                Text(
                                  'CATATAN UNTUK USAHAMU',
                                  style: TextStyle(
                                    color: SmartTokoTheme.forest,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              motivation,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Cepat, Pintar, dan Tanpa Ribet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718077),
                        ),
                      ),
                    ),
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

/// Tawaran memulihkan cadangan saat data toko di HP ini masih kosong —
/// biasanya karena baru ganti HP atau memasang ulang aplikasi.
class _RestoreOffer extends ConsumerStatefulWidget {
  const _RestoreOffer();

  @override
  ConsumerState<_RestoreOffer> createState() => _RestoreOfferState();
}

class _RestoreOfferState extends ConsumerState<_RestoreOffer> {
  bool _restoring = false;

  Future<void> _dismiss() async {
    final storeId = ref.read(activeStoreIdProvider);
    if (storeId == null) return;
    await ref
        .read(settingsDaoProvider)
        .setFlag(restoreOfferDismissedKey(storeId), value: true);
    ref.invalidate(restoreOfferProvider);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      await restoreBackup(context, ref);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backupAt = ref.watch(restoreOfferProvider).value;
    final syncOn = ref.watch(activeStoreProvider).value?.syncEnabled ?? false;
    // Karyawan tidak memulihkan cadangan; toko yang tersinkron sudah dipulihkan
    // dari server.
    if (backupAt == null || syncOn || ref.watch(isStaffProvider)) {
      return const SizedBox.shrink();
    }

    return MaterialBanner(
      leading: const Icon(Icons.cloud_download_outlined),
      content: Text(
        'Ada cadangan toko ini dari ${formatShortDate(backupAt)}. '
        'Pulihkan ke HP ini?',
      ),
      actions: [
        TextButton(
          onPressed: _restoring ? null : _dismiss,
          child: const Text('Nanti saja'),
        ),
        FilledButton(
          onPressed: _restoring ? null : _restore,
          child: const Text('Pulihkan'),
        ),
      ],
    );
  }
}

/// Nama toko aktif sebagai judul, supaya jelas pencatatan masuk ke toko mana
/// saat pemiliknya punya beberapa toko. Diketuk untuk ganti/tambah toko.
class _StoreTitle extends ConsumerWidget {
  final bool enabled;
  const _StoreTitle({this.enabled = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(activeStoreProvider).value;
    final verified =
        store?.verificationStatus == StoreVerificationStatus.verified;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: !enabled
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const StoreListScreen(isPicker: true),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                store?.name ?? 'SmartToko',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (verified) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Toko terverifikasi',
                child: Icon(Icons.verified, color: Colors.green, size: 20),
              ),
            ],
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final AsyncValue<ReportData> totals;
  final bool showProfit;
  const _TodaySummary({required this.totals, this.showProfit = true});

  @override
  Widget build(BuildContext context) {
    final value = totals.value?.current;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SmartTokoTheme.forest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 24,
            runSpacing: 8,
            children: [
              const Text(
                'Ringkasan hari ini',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatShortDate(DateTime.now()),
                style: const TextStyle(color: Color(0xFFD7EBDC), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Penjualan hari ini',
            style: TextStyle(color: Color(0xFFD7EBDC), fontSize: 13),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? '—' : formatRupiah(value.omzet),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cells = [
                if (showProfit)
                  _SummaryAmount(
                    label: 'Estimasi laba',
                    amount: value == null
                        ? null
                        : value.omzet - value.pengeluaran,
                  ),
                _SummaryAmount(
                  label: 'Bahan + operasional',
                  amount: value?.pengeluaran,
                ),
              ];
              return constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(14) > 22
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cells[0],
                        const SizedBox(height: 12),
                        cells[1],
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: cells[0]),
                        const SizedBox(width: 16),
                        Expanded(child: cells[1]),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          Text(
            totals.hasError
                ? 'Belum berhasil dimuat. Tarik layar untuk mencoba lagi.'
                : 'Estimasi dari penjualan dikurangi biaya tercatat.',
            style: const TextStyle(color: Color(0xFFD7EBDC), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _SummaryAmount extends StatelessWidget {
  final String label;
  final int? amount;
  const _SummaryAmount({required this.label, required this.amount});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD7EBDC), fontSize: 11),
      ),
      const SizedBox(height: 5),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          amount == null ? '—' : formatRupiah(amount!),
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    ],
  );
}

class _LowStockAlert extends ConsumerWidget {
  final bool enabled;
  const _LowStockAlert({required this.enabled});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lowStockProvider).value;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      color: const Color(0xFFFFF1DF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const FigmaIcon('d3e85'),
        title: Text(
          '${items.length} bahan perlu dibeli',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          items
              .take(2)
              .map(
                (i) =>
                    '${i.product.name}: ${formatQty(i.stock, i.product.unit)}',
              )
              .join(' · '),
          style: const TextStyle(fontSize: 12, color: Color(0xFFAD642C)),
        ),
        onTap: enabled
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const CatalogScreen(initialKind: ProductKind.bahan),
                ),
              )
            : null,
      ),
    );
  }
}

/// Ringkasan utang/piutang. Hanya muncul bila ada yang belum lunas.
class _DebtAlert extends ConsumerWidget {
  final bool enabled;
  const _DebtAlert({required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(debtTotalsProvider).value;
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();
    final overdue = totals.overdueReceivable + totals.overduePayable;
    final parts = [
      if (totals.receivable > 0) 'Ditagih ${formatRupiah(totals.receivable)}',
      if (totals.payable > 0) 'Dibayar ${formatRupiah(totals.payable)}',
      if (overdue > 0) '${formatRupiah(overdue)} telat',
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      color: const Color(0xFFFFF1DF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.handshake_outlined, color: Color(0xFFAD642C)),
        title: const Text(
          'Utang & piutang',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          parts.join(' · '),
          style: const TextStyle(fontSize: 12, color: Color(0xFFAD642C)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DebtsScreen()),
              )
            : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada catatan hari ini',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tekan tombol rekam, lalu sebutkan misalnya\n'
              '"jual indomie dua bungkus lima ribu"',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pintasan ke layar-layar pendukung. Sengaja satu baris kecil supaya
/// tombol rekam tetap jadi pusat perhatian.
class _QuickAccess extends StatelessWidget {
  final bool enabled;
  const _QuickAccess({required this.enabled});
  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          _QuickButton(
            asset: '9602a',
            label: 'Produk & Menu',
            onTap: enabled ? () => open(const CatalogScreen()) : null,
          ),
          const SizedBox(width: 10),
          _QuickButton(
            asset: 'b0f31',
            label: 'Relasi',
            onTap: enabled ? () => open(const ContactsScreen()) : null,
          ),
          const SizedBox(width: 10),
          _QuickButton(
            asset: 'b280b',
            label: 'Progres',
            onTap: enabled ? () => open(const RecordingProgressScreen()) : null,
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String asset;
  final String label;
  final VoidCallback? onTap;
  const _QuickButton({required this.asset, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E7DE)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              FigmaIcon(asset),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CaptureBar extends StatelessWidget {
  final CaptureState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onManual;

  const _CaptureBar({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listening = state is CaptureInProgress;
    final processing = state is CaptureProcessing;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state is CaptureInProgress &&
                      (state as CaptureInProgress).partialText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        (state as CaptureInProgress).partialText,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (processing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Memproses...'),
                    ),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 60,
                          child: FilledButton.icon(
                            onPressed: processing
                                ? null
                                : (listening ? onStop : onStart),
                            style: FilledButton.styleFrom(
                              backgroundColor: listening
                                  ? theme.colorScheme.error
                                  : null,
                            ),
                            icon: Icon(
                              listening ? Icons.stop : Icons.mic,
                              size: 28,
                            ),
                            label: Text(
                              listening ? 'Berhenti' : 'Rekam',
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 60,
                          child: OutlinedButton.icon(
                            onPressed: processing ? null : onManual,
                            icon: const Icon(Icons.keyboard),
                            label: const Text('Ketik'),
                          ),
                        ),
                      ),
                    ],
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
