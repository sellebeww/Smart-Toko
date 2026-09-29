/// Layar utama: satu tombol besar untuk mencatat.
///
/// Tata letaknya tunduk pada satu kasus pemakaian: tangan sibuk atau kotor.
/// Karena itu tombol rekam dibuat sangat besar dan berada di jangkauan ibu
/// jari, dan tombol "ketik manual" duduk tepat di sebelahnya dengan bobot yang
/// setara — bukan disembunyikan di menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../settings/ui/settings_screen.dart';
import '../../stores/stores_providers.dart';
import '../../stores/ui/store_list_screen.dart';
import '../../verification/domain/verification_status.dart';
import '../../voice_capture/capture_controller.dart';
import '../../voice_capture/speech_service.dart';
import '../../catalog/ui/catalog_screen.dart';
import '../../contacts/contacts_providers.dart';
import '../../contacts/ui/contacts_screen.dart';
import '../../reports/reports_providers.dart';
import '../../reports/ui/report_screen.dart';
import '../domain/transaction_draft.dart';
import '../transactions_providers.dart';
import 'history_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_editor.dart';
import 'transaction_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sheetOpen = false;

  Future<void> _openSheet(TransactionDraft draft) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    await showTransactionEditor(context, ref, draft: draft);
    _sheetOpen = false;
    if (mounted) ref.read(captureControllerProvider.notifier).reset();
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
    final totals = ref.watch(todayTotalsProvider);
    final transactions = ref.watch(todayTransactionsProvider);
    final motivation = ref.watch(dailyMotivationProvider).value;
    final contactNames = ref.watch(contactNamesProvider).value ?? const {};
    final pending = ref.watch(pendingTxIdsProvider).value ?? const {};
    final capturing =
        captureState is CaptureInProgress || captureState is CaptureProcessing;

    return Scaffold(
      appBar: AppBar(
        title: _StoreTitle(enabled: !capturing),
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
      body: Column(
        children: [
          _TodaySummary(totals: totals, motivation: motivation),
          _QuickAccess(enabled: !capturing),
          Expanded(
            child: transactions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Gagal memuat: $error')),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final r = items[index];
                        return TransactionTile(
                          record: r,
                          contactName: r.contactId == null
                              ? null
                              : contactNames[r.contactId],
                          pendingSync: pending.contains(r.id),
                          onTap: capturing
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TransactionDetailScreen(
                                      transactionId: r.id,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ),
          _CaptureBar(
            state: captureState,
            onStart: () => ref.read(captureControllerProvider.notifier).start(),
            onStop: () => ref.read(captureControllerProvider.notifier).stop(),
            onManual: () async {
              await ref.read(captureControllerProvider.notifier).cancel();
              if (mounted) await _openSheet(TransactionDraft.manual());
            },
          ),
        ],
      ),
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
  final AsyncValue<DayTotals> totals;
  final String? motivation;

  const _TodaySummary({required this.totals, this.motivation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = totals.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDayMonth(DateTime.now()),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TotalTile(
                  label: 'Masuk',
                  amount: value?.masuk,
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _TotalTile(
                  label: 'Keluar',
                  amount: value?.keluar,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          if (motivation case final text? when text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  final String label;
  final int? amount;
  final Color color;

  const _TotalTile({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(
          amount == null ? '—' : formatRupiah(amount!),
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          _QuickButton(
            icon: Icons.receipt_long_outlined,
            label: 'Riwayat',
            onTap: enabled ? () => open(const HistoryScreen()) : null,
          ),
          _QuickButton(
            icon: Icons.insights_outlined,
            label: 'Laporan',
            onTap: enabled ? () => open(const ReportScreen()) : null,
          ),
          _QuickButton(
            icon: Icons.inventory_2_outlined,
            label: 'Stok',
            onTap: enabled ? () => open(const CatalogScreen()) : null,
          ),
          _QuickButton(
            icon: Icons.people_outline,
            label: 'Kontak',
            onTap: enabled ? () => open(const ContactsScreen()) : null,
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  icon,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                    height: 72,
                    child: FilledButton.icon(
                      onPressed: processing
                          ? null
                          : (listening ? onStop : onStart),
                      style: FilledButton.styleFrom(
                        backgroundColor: listening
                            ? theme.colorScheme.error
                            : null,
                      ),
                      icon: Icon(listening ? Icons.stop : Icons.mic, size: 28),
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
                    height: 72,
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
    );
  }
}
