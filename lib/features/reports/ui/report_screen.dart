/// Dasbor laporan: omzet, pengeluaran, keuntungan perkiraan, menu terlaris,
/// stok menipis, dan wawasan dibanding periode sebelumnya.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/product_dao.dart';
import '../../../core/format.dart';
import '../../../core/ui/figma_icon.dart';
import '../../../core/transaction_kind.dart';
import '../../catalog/ui/catalog_screen.dart';
import '../../export/export_service.dart';
import '../data/report_repository.dart';
import '../domain/insights.dart';
import '../reports_providers.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportPeriod _period = ReportPeriod.hariIni;

  bool _exporting = false;

  Future<void> _export(ReportData data) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final records = await ref
          .read(transactionRepositoryProvider)
          .listBetween(
            storeId: ref.read(activeStoreIdProvider)!,
            from: data.from,
            to: data.to,
          );
      if (!mounted) return;
      await exportTransactions(
        context,
        ref,
        records: records,
        from: data.from,
        toInclusive: data.to.subtract(const Duration(days: 1)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Laporan belum bisa diekspor. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportProvider(_period));

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan & Insight')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<ReportPeriod>(
              segments: [
                for (final p in ReportPeriod.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
          ),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (data) => _ReportBody(
                data: data,
                onExport: _exporting ? null : () => _export(data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final ReportData data;
  final VoidCallback? onExport;

  const _ReportBody({required this.data, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = data.current;
    final p = data.previous;
    final vs = data.period.previousLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F2E9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RINGKASAN ${data.period.label.toUpperCase()}',
                style: const TextStyle(
                  color: Color(0xFF176448),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Omzet ${data.period.label.toLowerCase()}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRupiah(c.omzet),
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 14),
              Text(
                '${c.count} transaksi tercatat',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '${formatShortDate(data.from)} – ${formatShortDate(data.to.subtract(const Duration(days: 1)))}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Total biaya',
                amount: c.pengeluaran,
                previous: p.pengeluaran,
                vs: vs,
                color: theme.colorScheme.onSurface,
                higherIsBetter: false,
              ),
            ),
            Expanded(
              child: _MetricCard(
                label: 'Estimasi laba',
                amount: c.omzet - c.pengeluaran,
                previous: p.omzet - p.pengeluaran,
                vs: vs,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            'Estimasi laba = omzet − biaya tercatat. Pembelian stok belum tentu habis terpakai pada periode ini.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (c.of(TxCategory.pemasukanLain) > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              'Termasuk pemasukan lain ${formatRupiah(c.of(TxCategory.pemasukanLain))} '
              'di luar omzet.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        _Section(
          icon: Icons.lightbulb_outline,
          title: 'Wawasan',
          child: data.insights.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Belum ada data pada periode ini. Wawasan muncul setelah '
                    'ada transaksi tercatat.',
                  ),
                )
              : Column(
                  children: [
                    for (final text in data.insights)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.arrow_right),
                        minLeadingWidth: 0,
                        title: Text(text, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ),
        ),
        if (data.daily.isNotEmpty)
          _Section(
            icon: Icons.bar_chart,
            title: 'Uang masuk & keluar per hari',
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _DailyBars(
                from: data.from,
                to: data.to,
                daily: data.daily,
              ),
            ),
          ),
        _Section(
          icon: Icons.savings_outlined,
          title: 'Laba per menu',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CatalogScreen()),
            ),
            child: const Text('Atur modal'),
          ),
          child: _GrossProfitView(profit: data.grossProfit),
        ),
        _Section(
          icon: Icons.restaurant_menu,
          title: 'Menu terlaris',
          child: _ItemList(
            items: data.topMenu,
            empty: 'Belum ada penjualan tercatat.',
            showQty: true,
          ),
        ),
        _Section(
          icon: Icons.shopping_basket_outlined,
          title: 'Pengeluaran terbesar',
          child: _ItemList(
            items: data.topSpending,
            empty: 'Belum ada pengeluaran tercatat.',
            showQty: false,
          ),
        ),
        _Section(
          icon: Icons.inventory_2_outlined,
          title: 'Kondisi stok',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const CatalogScreen(initialKind: ProductKind.bahan),
              ),
            ),
            child: const Text('Lihat stok'),
          ),
          child: data.lowStock.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tidak ada bahan yang menipis. Atur batas minimum di '
                    'menu Stok agar diingatkan.',
                  ),
                )
              : Column(
                  children: [
                    for (final s in data.lowStock)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.warning_amber,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(s.product.name),
                        trailing: Text(
                          'sisa ${formatQty(s.stock, s.product.unit)}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: onExport,
          icon: const FigmaIcon('8b6fb'),
          label: Text(
            onExport == null
                ? 'Menyiapkan laporan…'
                : 'Ekspor Excel (${data.period.label.toLowerCase()})',
          ),
        ),
      ],
    );
  }
}

/// Laba kotor = omzet menu − modal saat terjual. Hanya menu yang modalnya
/// diisi yang dihitung; sisanya disebut terang-terangan.
class _GrossProfitView extends StatelessWidget {
  final GrossProfit profit;
  const _GrossProfitView({required this.profit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (profit.menus.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Belum ada penjualan pada periode ini.'),
      );
    }
    if (profit.costedRevenue == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Isi modal per porsi di daftar Menu supaya laba tiap menu bisa '
          'dihitung. Cukup sekali; penjualan sebelumnya ikut terhitung.',
        ),
      );
    }
    final missing = profit.missingCost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Laba kotor ${formatRupiah(profit.profit)}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: profit.profit < 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(
            profit.coveragePercent >= 100
                ? 'Omzet menu dikurangi modal saat terjual.'
                : 'Dari ${profit.coveragePercent}% omzet yang modalnya '
                      'diketahui.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final m in profit.menus.where((m) => m.hasCost).take(5))
          ListTile(
            dense: true,
            title: Text(m.name),
            subtitle: Text(
              '${formatQty(m.qty, m.unit)} terjual · margin ${m.marginPercent}%',
            ),
            trailing: Text(
              formatRupiah(m.profit!),
              style: theme.textTheme.titleSmall?.copyWith(
                color: m.profit! < 0 ? theme.colorScheme.error : null,
              ),
            ),
          ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Modal belum diisi: '
              '${missing.take(3).map((m) => m.name).join(', ')}'
              '${missing.length > 3 ? ' dan ${missing.length - 3} lainnya' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int? amount;
  final int previous;
  final String vs;
  final Color color;
  final bool higherIsBetter;

  const _MetricCard({
    required this.label,
    required this.previous,
    required this.vs,
    required this.color,
    this.amount,
    this.higherIsBetter = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = amount ?? 0;
    final pct = percentChange(value, previous);
    final good = pct == null || pct == 0 || (pct > 0) == higherIsBetter;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatRupiah(value),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pct == null
                  ? 'belum ada data $vs'
                  : pct == 0
                  ? 'sama dengan $vs'
                  : '${pct > 0 ? '▲' : '▼'} ${pct.abs()}% vs $vs',
              style: theme.textTheme.bodySmall?.copyWith(
                color: pct == null || pct == 0
                    ? theme.colorScheme.outline
                    : good
                    ? Colors.green.shade700
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, trailing == null ? 16 : 4, 0),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  final List<ItemAggregate> items;
  final String empty;
  final bool showQty;

  const _ItemList({
    required this.items,
    required this.empty,
    required this.showQty,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(empty));
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (i, item) in items.indexed)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}', style: theme.textTheme.labelMedium),
            ),
            title: Text(item.name),
            subtitle: showQty ? Text(formatQty(item.qty, item.unit)) : null,
            trailing: Text(
              formatRupiah(item.amount),
              style: theme.textTheme.titleSmall,
            ),
          ),
      ],
    );
  }
}

/// Grafik batang sederhana tanpa pustaka tambahan: dua batang per hari
/// (masuk hijau, keluar merah), tinggi relatif terhadap nilai terbesar.
class _DailyBars extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final Map<DateTime, ({int masuk, int keluar})> daily;

  const _DailyBars({required this.from, required this.to, required this.daily});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = <DateTime>[
      for (
        var d = from;
        d.isBefore(to);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    var max = 1;
    for (final v in daily.values) {
      if (v.masuk > max) max = v.masuk;
      if (v.keluar > max) max = v.keluar;
    }
    const height = 120.0;
    final showEveryLabel = days.length <= 7;

    return Column(
      children: [
        SizedBox(
          height: height + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, day) in days.indexed)
                Expanded(
                  child: Tooltip(
                    message:
                        '${formatShortDate(day)}\n'
                        'Masuk ${formatRupiah(daily[day]?.masuk ?? 0)}\n'
                        'Keluar ${formatRupiah(daily[day]?.keluar ?? 0)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _bar(
                              (daily[day]?.masuk ?? 0) / max * height,
                              theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 1),
                            _bar(
                              (daily[day]?.keluar ?? 0) / max * height,
                              theme.colorScheme.error,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 16,
                          child: (showEveryLabel || i % 5 == 0)
                              ? Text(
                                  showEveryLabel ? _weekday(day) : '${day.day}',
                                  style: theme.textTheme.labelSmall,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(theme.colorScheme.primary, 'Masuk'),
            const SizedBox(width: 16),
            _legend(theme.colorScheme.error, 'Keluar'),
          ],
        ),
      ],
    );
  }

  static String _weekday(DateTime d) =>
      const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d.weekday - 1];

  Widget _bar(double h, Color color) => Flexible(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 12),
      height: h < 1 && h > 0 ? 1 : h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    ),
  );

  Widget _legend(Color color, String label) => Row(
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
