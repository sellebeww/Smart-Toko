/// Empat slot foto untuk pengajuan verifikasi: KTP, foto toko, selfie
/// (semua wajib), dan NIB (opsional). Setelah submit, semua diunggah ke
/// Supabase Storage lalu status toko diubah jadi "Menunggu Verifikasi".
///
/// Salinan foto yang dibuat image_picker di cache aplikasi dihapus saat layar
/// ini ditutup (berhasil atau batal) — KTP dan selfie tidak boleh tertinggal
/// di HP.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../auth/auth_providers.dart';
import '../data/verification_repository.dart';

enum _Slot {
  ktp(
    'KTP pemilik',
    VerificationDocument.ktp,
    required: true,
    cameraOnly: false,
  ),
  storePhoto(
    'Foto toko dari luar',
    VerificationDocument.storePhoto,
    required: true,
    cameraOnly: false,
  ),
  // Kamera saja: selfie harus diambil saat itu juga, bukan foto lama.
  selfie(
    'Selfie sambil pegang KTP',
    VerificationDocument.selfie,
    required: true,
    cameraOnly: true,
  ),
  nib(
    'NIB / izin usaha',
    VerificationDocument.nib,
    required: false,
    cameraOnly: false,
  );

  final String title;
  final VerificationDocument document;
  final bool required;
  final bool cameraOnly;

  const _Slot(
    this.title,
    this.document, {
    required this.required,
    required this.cameraOnly,
  });

  Future<void> upload(
    VerificationRepository repo,
    String ownerUid,
    String storeId,
    File file,
  ) => repo.upload(ownerUid, storeId, document, file);
}

class UploadScreen extends ConsumerStatefulWidget {
  final String storeId;
  final String storeName;
  final String consentVersion;

  const UploadScreen({
    super.key,
    required this.storeId,
    required this.storeName,
    required this.consentVersion,
  });

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final Map<_Slot, File> _files = {};
  bool _submitting = false;
  bool _picking = false;
  int _uploaded = 0;
  String? _errorText;

  @override
  void dispose() {
    _files.values.forEach(_discard);
    super.dispose();
  }

  void _discard(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Berkas cache; kalau gagal dihapus, sistem tetap akan membersihkannya.
    }
  }

  bool get _canSubmit =>
      _Slot.values.where((s) => s.required).every(_files.containsKey);

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(_Slot slot) async {
    if (_picking || _submitting) return;
    setState(() => _picking = true);
    try {
      final source = slot.cameraOnly
          ? ImageSource.camera
          : await _chooseSource();
      if (source == null || !mounted) return;
      // imageQuality < 100 membuat image_picker selalu menulis salinan baru
      // di cache aplikasi — jadi yang nanti dihapus adalah salinan itu, bukan
      // foto asli di galeri pengguna.
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        preferredCameraDevice: slot == _Slot.selfie
            ? CameraDevice.front
            : CameraDevice.rear,
      );
      if (picked == null) return;
      final file = File(picked.path);
      if (!mounted) {
        _discard(file);
        return;
      }
      if (await file.length() >= 10 * 1024 * 1024) {
        _discard(file);
        if (mounted) {
          setState(
            () =>
                _errorText = 'Foto terlalu besar. Pilih gambar di bawah 10 MB.',
          );
        }
        return;
      }
      if (!mounted) {
        _discard(file);
        return;
      }
      final previous = _files[slot];
      setState(() {
        _files[slot] = file;
        _errorText = null;
      });
      if (previous != null && previous.path != file.path) _discard(previous);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak bisa membuka kamera atau galeri. Pastikan izin kamera sudah diberikan.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting || _picking) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final connectivity = ref.read(connectivityProvider);
    final verificationRepository = ref.read(verificationRepositoryProvider);
    final storeRepository = ref.read(storeRepositoryProvider);
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null) return;

    setState(() {
      _submitting = true;
      _uploaded = 0;
      _errorText = null;
    });
    try {
      if (!await connectivity.isOnline()) {
        if (mounted) {
          setState(
            () => _errorText = 'Butuh koneksi internet untuk mengunggah. Coba lagi saat online.',
          );
        }
        return;
      }

      if (!mounted) return;
      for (final MapEntry(key: slot, value: file) in _files.entries.toList()) {
        await slot.upload(verificationRepository, uid, widget.storeId, file);
        if (!mounted) return;
        setState(() => _uploaded++);
      }
      await storeRepository
          .submitForVerification(
            widget.storeId,
            consentVersion: widget.consentVersion,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      // Kembali ke Pengaturan (tutup layar unggah dan layar persetujuan),
      // tempat status "Menunggu Verifikasi" langsung terlihat.
      navigator
        ..pop()
        ..pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Pengajuan verifikasi terkirim')),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal mengirim pengajuan. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // Jangan tinggalkan layar di tengah unggahan: berkasnya bisa setengah
      // terkirim sementara status toko belum berubah.
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: Text('Unggah — ${widget.storeName}')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final slot in _Slot.values) ...[
                _UploadSlot(
                  slot: slot,
                  file: _files[slot],
                  onTap: (_submitting || _picking) ? null : () => _pick(slot),
                ),
                const SizedBox(height: 12),
              ],
              if (_submitting) ...[
                LinearProgressIndicator(value: _uploaded / _files.length),
                const SizedBox(height: 8),
                Text(
                  _uploaded == _files.length
                      ? 'Mengirim pengajuan…'
                      : 'Mengunggah foto ${_uploaded + 1} dari ${_files.length}…',
                ),
                const SizedBox(height: 12),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_canSubmit && !_submitting && !_picking)
                    ? _submit
                    : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kirim untuk Diverifikasi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadSlot extends StatelessWidget {
  final _Slot slot;
  final File? file;
  final VoidCallback? onTap;

  const _UploadSlot({
    required this.slot,
    required this.file,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = file;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: picked != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  picked,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            : Icon(
                slot.cameraOnly
                    ? Icons.camera_front_outlined
                    : Icons.add_a_photo_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        title: Text(slot.required ? slot.title : '${slot.title} (opsional)'),
        subtitle: Text(
          picked != null
              ? 'Sudah ada — ketuk untuk ganti'
              : slot.cameraOnly
              ? 'Ketuk untuk memotret (kamera depan)'
              : 'Ketuk untuk memotret atau pilih dari galeri',
        ),
        trailing: picked != null
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      ),
    );
  }
}
