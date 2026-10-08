/// Form tambah toko. Wajib diisi minimal sekali per akun (gerbang di
/// app/app.dart menampilkan ini kalau user belum punya toko sama sekali),
/// dan bisa dibuka lagi kapan pun untuk menambah toko lain. Dengan
/// [AddStoreScreen.existing], form yang sama dipakai mengubah profil toko.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../auth/auth_providers.dart';
import '../domain/store_profile.dart';

class AddStoreScreen extends ConsumerStatefulWidget {
  final bool isFirstStore;

  /// Diisi untuk mengubah profil toko yang sudah ada.
  final StoreProfile? existing;

  const AddStoreScreen({super.key, this.isFirstStore = true, this.existing});

  bool get isEditing => existing != null;

  @override
  ConsumerState<AddStoreScreen> createState() => _AddStoreScreenState();
}

class _AddStoreScreenState extends ConsumerState<AddStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name,
  );
  late final _addressController = TextEditingController(
    text: widget.existing?.address,
  );
  late StoreCategory _category =
      widget.existing?.category ?? StoreCategory.warteg;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveEdit(StoreProfile store) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(storeRepositoryProvider)
          .updateProfile(
            store.id,
            name: _nameController.text.trim(),
            category: _category,
            address: _addressController.text.trim(),
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Profil toko disimpan')),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal menyimpan. Mengubah profil toko butuh koneksi internet.',
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    if (widget.existing case final store?) {
      await _saveEdit(store);
      if (mounted) setState(() => _submitting = false);
      return;
    }
    // Diambil sebelum await: begitu toko baru muncul di server, gerbang toko
    // bisa mengganti layar ini sebelum _submit selesai.
    final uid = ref.read(authStateChangesProvider).value!.uid;
    final storeDao = ref.read(storeDaoProvider);
    final storeRepository = ref.read(storeRepositoryProvider);
    final activeStore = ref.read(activeStoreIdProvider.notifier);
    final previousActiveId = ref.read(activeStoreIdProvider);
    final navigator = Navigator.of(context);
    final id = const Uuid().v4();
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final category = _category;

    try {
      // Baris lokal dan toko aktif disiapkan DULU, supaya saat toko ini
      // muncul di server gerbang langsung membuka Home tanpa singgah di
      // daftar toko.
      await storeDao.ensureExists(id, name);
      if (!mounted) return;
      await activeStore.set(id);
      if (!mounted) return;
      await storeRepository.create(
        id: id,
        ownerUid: uid,
        name: name,
        category: category,
        address: address,
      );

      if (mounted && !widget.isFirstStore) navigator.pop(id);
    } catch (e) {
      if (mounted) {
        try {
          await activeStore.set(previousActiveId);
        } catch (_) {
          // Tampilkan kegagalan awal meskipun penyimpanan lokal juga gagal.
        }
      }
      if (mounted) {
        setState(() => _errorText = 'Gagal menyimpan toko, coba lagi');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: widget.isEditing
          ? AppBar(title: const Text('Ubah Profil Toko'))
          : widget.isFirstStore
          ? null
          : AppBar(title: const Text('Tambah Toko')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isFirstStore && !widget.isEditing) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Tambah Toko Baru',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Isi data toko kamu dulu sebelum mulai mencatat.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nama toko'),
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Wajib diisi'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<StoreCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Kategori usaha',
                  ),
                  items: StoreCategory.values
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.label)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Alamat toko'),
                  maxLines: 2,
                  maxLength: 300,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Wajib diisi'
                      : null,
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.isEditing ? 'Simpan Perubahan' : 'Simpan Toko',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
