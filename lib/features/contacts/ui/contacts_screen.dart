/// Daftar pelanggan dan supplier beserta ringkasan transaksinya.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/dao/contact_dao.dart';
import '../../../core/format.dart';
import '../contacts_providers.dart';
import 'contact_detail_screen.dart';
import 'contact_form_sheet.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Relasi'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.people_outline), text: 'Pelanggan'),
                Tab(
                  icon: Icon(Icons.local_shipping_outlined),
                  text: 'Supplier',
                ),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _ContactList(kind: ContactKind.pelanggan),
              _ContactList(kind: ContactKind.supplier),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showContactForm(
              context,
              kind: DefaultTabController.of(context).index == 0
                  ? ContactKind.pelanggan
                  : ContactKind.supplier,
            ),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Tambah'),
          ),
        ),
      ),
    );
  }
}

class _ContactList extends ConsumerWidget {
  final ContactKind kind;

  const _ContactList({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider(kind));
    final stats = ref.watch(contactStatsProvider).value ?? const {};
    final theme = Theme.of(context);

    return contacts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                kind == ContactKind.pelanggan
                    ? 'Belum ada pelanggan. Tambahkan pelanggan tetap atau '
                          'pesanan katering, lalu pilih saat mencatat penjualan.'
                    : 'Belum ada supplier. Tambahkan pemasok bahan, lalu '
                          'pilih saat mencatat pembelian.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // Sebaran lokasi: membantu melihat dari mana pelanggan datang.
        final byLocation = <String, int>{};
        for (final c in items) {
          final loc = c.location?.trim();
          if (loc == null || loc.isEmpty) continue;
          byLocation[loc] = (byLocation[loc] ?? 0) + 1;
        }
        final locations = byLocation.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Yang paling sering bertransaksi di atas.
        final sorted = [...items]
          ..sort((a, b) {
            final sa = stats[a.id] ?? ContactStats.empty;
            final sb = stats[b.id] ?? ContactStats.empty;
            final byTotal = sb.totalAmount.compareTo(sa.totalAmount);
            return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
          });

        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (locations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sebaran lokasi', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final e in locations.take(8))
                          Chip(
                            avatar: const Icon(Icons.place_outlined, size: 16),
                            label: Text('${e.key} · ${e.value}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            for (final c in sorted)
              _ContactTile(
                contact: c,
                stats: stats[c.id] ?? ContactStats.empty,
              ),
          ],
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactRecord contact;
  final ContactStats stats;

  const _ContactTile({required this.contact, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            contact.name.isEmpty
                ? '?'
                : contact.name.characters.first.toUpperCase(),
          ),
        ),
        title: Text(contact.name),
        subtitle: Text(
          [
            ?contact.location,
            stats.transactionCount == 0
                ? 'belum ada transaksi'
                : '${stats.transactionCount}× transaksi',
          ].join(' · '),
        ),
        trailing: stats.totalAmount == 0
            ? null
            : Text(
                formatRupiah(stats.totalAmount),
                style: theme.textTheme.titleSmall,
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContactDetailScreen(contactId: contact.id),
          ),
        ),
      ),
    );
  }
}
