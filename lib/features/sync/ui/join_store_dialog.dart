/// Bergabung ke toko sebagai karyawan dengan kode dari pemilik.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../stores/stores_providers.dart';
import '../sync_providers.dart';
import '../team_repository.dart';

/// Mengembalikan true bila berhasil bergabung (toko langsung dibuka).
Future<bool> showJoinStoreDialog(BuildContext context, WidgetRef ref) async {
  final joined = await showDialog<String>(
    context: context,
    builder: (_) => const _JoinDialog(),
  );
  if (joined == null) return false;
  ref.invalidate(userStoresProvider);
  try {
    final stores = await ref.read(userStoresProvider.future);
    final store = stores.where((s) => s.id == joined).firstOrNull;
    if (store != null) {
      await ref.read(storeDaoProvider).ensureExists(store.id, store.name);
      await ref.read(activeStoreIdProvider.notifier).set(store.id);
    }
  } catch (_) {
    // Daftar toko akan menampilkannya begitu termuat.
  }
  return true;
}

class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog();

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  final TextEditingController _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (normalizeInviteCode(_code.text).length != 10) {
      setState(() => _error = 'Kode terdiri dari 10 huruf/angka.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final storeId = await ref
          .read(teamRepositoryProvider)
          .acceptInvite(_code.text);
      if (!mounted) return;
      if (storeId == null) {
        setState(
          () => _error =
              'Kode salah, sudah dipakai, atau kedaluwarsa. Minta kode baru '
              'ke pemilik toko.',
        );
      } else {
        Navigator.of(context).pop(storeId);
      }
    } on TeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Belum bisa terhubung. Periksa internet.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gabung toko'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Masukkan kode undangan dari pemilik toko. Kamu bisa mencatat '
          'transaksi untuk toko itu dari HP-mu.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Kode undangan',
            hintText: 'ABCDE-12345',
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _join(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _busy ? null : _join,
        child: const Text('Gabung'),
      ),
    ],
  );
}
