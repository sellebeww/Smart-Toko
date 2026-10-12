/// Riwayat transaksi: filter tanggal/kategori/sumber, dikelompokkan per hari
/// dengan subtotal, dan bisa diekspor ke Excel.
library;

import '../../sync/sync_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import '../../contacts/contacts_providers.dart';
import '../../export/export_service.dart';
import '../domain/history_filter.dart';
import '../history_providers.dart';
import 'transaction_detail_screen.dart';
import 'transaction_tile.dart';
import 'text_entry_sheet.dart';
import 'transaction_editor.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref, bool all) async {
    if (all) return exportAllTransactions(context, ref);
    final records = await ref.read(historyTransactionsProvider.future);
    final range = ref.read(historyFilterProvider).resolve(DateTime.now());
    if (!context.mounted) return;
    await exportTransactions(
      context,
      ref,
      records: records,
      from: range.from,
      toInclusive: range.to.subtract(const Duration(days: 1)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final transactions = ref.watch(historyTransactionsProvider);
    final contactNames = ref.watch(contactNamesProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          // Ekspor membuka seluruh angka toko; hanya untuk pemilik.
          if (!ref.watch(isStaffProvider))
            PopupMenuButton<bool>(
              tooltip: 'Export Excel',
              icon: const Icon(Icons.file_download_outlined),
              onSelected: (all) => _export(context, ref, all),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  child: Text(
                    filter.isNarrowed
                        ? 'Export sesuai filter'
                        : 'Export ${filter.range.label.toLowerCase()}',
                  ),
                ),
                const PopupMenuItem(
                  value: true,
                  child: Text('Export semua data toko ini'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final draft = await showTextEntry(context);
          if (draft != null && context.mounted) {
            await showTransactionEditor(context, ref, draft: draft);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Catat transaksi'),
      ),
      body: Column(
        children: [
          _SearchField(query: filter.query),
          _FilterBar(filter: filter),
          const Divider(height: 1),
          Expanded(
            child: transactions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (records) {
                if (records.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        filter.isNarrowed
                            ? 'Tidak ada transaksi yang cocok dengan filter.'
                            : 'Belum ada transaksi pada rentang ini.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final groups = groupByDay(records);
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _RangeSummary(groups: groups)),
                    for (final group in groups) ...[
                      SliverToBoxAdapter(child: _DayHeader(group: group)),
                      SliverList.builder(
                        itemCount: group.records.length,
                        itemBuilder: (context, i) {
                          final r = group.records[i];
                          return TransactionTile(
                            record: r,
                            contactName: r.contactId == null
                                ? null
                                : contactNames[r.contactId],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TransactionDetailScreen(
                                  transactionId: r.id,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Kolom cari. Teksnya milik widget ini (bukan di-rebuild dari filter),
/// supaya kursor tidak melompat saat daftar dimuat ulang tiap ketikan.
class _SearchField extends ConsumerStatefulWidget {
  final String query;
  const _SearchField({required this.query});

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(_SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Filter direset dari luar (mis. ganti toko).
    if (widget.query != _controller.text.trim() && widget.query.isEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String value) {
    final notifier = ref.read(historyFilterProvider.notifier);
    notifier.set(ref.read(historyFilterProvider).copyWith(query: value));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: TextField(
      controller: _controller,
      onChanged: _apply,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Cari barang, catatan, atau nama',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus pencarian',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  _apply('');
                  setState(() {});
                },
              ),
      ),
    ),
  );
}

class _FilterBar extends ConsumerWidget {
  final HistoryFilter filter;

  const _FilterBar({required this.filter});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: filter.range == HistoryRange.pilihTanggal
          ? DateTimeRange(
              start: filter.customFrom ?? now,
              end: filter.customTo ?? now,
            )
          : null,
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (picked == null) return;
    ref
        .read(historyFilterProvider.notifier)
        .set(
          filter.copyWith(
            range: HistoryRange.pilihTanggal,
            customFrom: picked.start,
            customTo: picked.end,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyFilterProvider.notifier);

    String rangeLabel(HistoryRange r) {
      if (r == HistoryRange.pilihTanggal &&
          filter.range == r &&
          filter.customFrom != null) {
        final from = formatShortDate(filter.customFrom!);
        final to = formatShortDate(filter.customTo ?? filter.customFrom!);
        return from == to ? from : '$from – $to';
      }
      return r.label;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final r in HistoryRange.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(rangeLabel(r)),
                      avatar: r == HistoryRange.pilihTanggal
                          ? const Icon(Icons.date_range, size: 18)
                          : null,
                      selected: filter.range == r,
                      onSelected: (_) => r == HistoryRange.pilihTanggal
                          ? _pickRange(context, ref)
                          : notifier.set(filter.copyWith(range: r)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: const Icon(Icons.hourglass_bottom, size: 16),
                    label: const Text('Belum lunas'),
                    selected: filter.onlyUnpaid,
                    onSelected: (on) =>
                        notifier.set(filter.copyWith(onlyUnpaid: on)),
                  ),
                ),
                for (final c in TxCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c.label),
                      selected: filter.categories.contains(c),
                      onSelected: (on) => notifier.set(
                        filter.copyWith(
                          categories: on
                              ? {...filter.categories, c}
                              : ({...filter.categories}..remove(c)),
                        ),
                      ),
                    ),
                  ),
                // Nilai null dianggap "batal" oleh PopupMenuButton, jadi
                // "semua sumber" diwakili string.
                PopupMenuButton<Object>(
                  tooltip: 'Sumber',
                  onSelected: (s) => notifier.set(
                    filter.copyWith(source: s is TxSource ? s : null),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'all',
                      child: Text('Semua sumber'),
                    ),
                    for (final s in TxSource.values)
                      PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: Chip(
                    avatar: Icon(
                      filter.source == null
                          ? Icons.filter_list
                          : TransactionTile.sourceIcon(filter.source!),
                      size: 18,
                    ),
                    label: Text(filter.source?.label ?? 'Semua sumber'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeSummary extends StatelessWidget {
  final List<DayGroup> groups;

  const _RangeSummary({required this.groups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var masuk = 0, keluar = 0, count = 0;
    for (final g in groups) {
      masuk += g.masuk;
      keluar += g.keluar;
      count += g.records.length;
    }
    Widget cell(String label, int amount, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRupiah(amount),
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count transaksi', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                cell('Masuk', masuk, theme.colorScheme.primary),
                cell('Keluar', keluar, theme.colorScheme.error),
                cell(
                  'Selisih',
                  masuk - keluar,
                  masuk >= keluar
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DayGroup group;

  const _DayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = group.net;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatDayHeader(group.day),
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            '${net >= 0 ? '+' : '−'}${formatRupiah(net.abs())}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: net >= 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
