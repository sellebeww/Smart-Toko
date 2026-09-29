/// Daftar toko milik user.
///
/// Dua mode:
/// - Gerbang (bawaan): tampil saat belum ada toko aktif. Langsung memilihkan
///   toko kalau cuma ada satu, atau kalau toko terakhir yang dipakai di
///   perangkat ini masih ada. Pemilihan dijadwalkan lewat post-frame callback,
///   bukan di build(), supaya tidak mengubah provider saat widget tree
///   dibangun.
/// - Pemilih ([isPicker]): dibuka dari layar utama untuk ganti atau tambah
///   toko; tidak memilih otomatis dan menutup diri setelah memilih.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../verification/domain/verification_status.dart';
import '../domain/store_profile.dart';
import '../stores_providers.dart';
import 'add_store_screen.dart';

class StoreListScreen extends ConsumerStatefulWidget {
  final bool isPicker;

  const StoreListScreen({super.key, this.isPicker = false});

  @override
  ConsumerState<StoreListScreen> createState() => _StoreListScreenState();
}

class _StoreListScreenState extends ConsumerState<StoreListScreen> {
  bool _autoSelectScheduled = false;
  bool _selecting = false;

  Future<void> _select(StoreProfile store) async {
    if (!mounted || _selecting) return;
    setState(() => _selecting = true);
    final activeStore = ref.read(activeStoreIdProvider.notifier);
    final navigator = Navigator.of(context);
    try {
      await ref.read(storeDaoProvider).ensureExists(store.id, store.name);
      if (!mounted) return;
      await activeStore.set(store.id);
      if (widget.isPicker && mounted) navigator.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuka toko. Ketuk toko untuk mencoba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _addStore() async {
    final navigator = Navigator.of(context);
    final createdId = await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => const AddStoreScreen(isFirstStore: false),
      ),
    );
    // Toko baru sudah dijadikan aktif oleh AddStoreScreen; di mode pemilih
    // langsung kembali ke layar utama.
    if (createdId != null && widget.isPicker && mounted) navigator.pop();
  }

  void _maybeAutoSelect(List<StoreProfile> stores, String? savedId) {
    if (widget.isPicker || _autoSelectScheduled) return;

    StoreProfile? preferred;
    if (stores.length == 1) {
      preferred = stores.first;
    } else if (savedId != null) {
      preferred = stores.where((s) => s.id == savedId).firstOrNull;
    }
    if (preferred == null) return;

    _autoSelectScheduled = true;
    final store = preferred;
    WidgetsBinding.instance.addPostFrameCallback((_) => _select(store));
  }

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(userStoresProvider);
    final savedId = ref.watch(savedActiveStoreIdProvider).value;
    final activeId = ref.watch(activeStoreIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPicker ? 'Ganti Toko' : 'Pilih Toko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Tambah toko',
            onPressed: _selecting ? null : _addStore,
          ),
        ],
      ),
      body: storesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Gagal memuat toko: $error')),
        data: (stores) {
          _maybeAutoSelect(stores, savedId);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stores.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final store = stores[index];
              final isActive = widget.isPicker && store.id == activeId;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          store.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (store.verificationStatus ==
                          StoreVerificationStatus.verified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 18,
                          color: Colors.green,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('${store.category.label} · ${store.address}'),
                  trailing: isActive ? const Icon(Icons.check) : null,
                  onTap: _selecting ? null : () => _select(store),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
