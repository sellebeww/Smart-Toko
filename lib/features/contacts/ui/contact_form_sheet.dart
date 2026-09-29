/// Form tambah/ubah pelanggan atau supplier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/dao/contact_dao.dart';

/// Mengembalikan kontak yang tersimpan, atau null bila dibatalkan.
Future<ContactRecord?> showContactForm(
  BuildContext context, {
  required ContactKind kind,
  ContactRecord? existing,
}) {
  return showModalBottomSheet<ContactRecord>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ContactForm(kind: kind, existing: existing),
  );
}

class _ContactForm extends ConsumerStatefulWidget {
  final ContactKind kind;
  final ContactRecord? existing;

  const _ContactForm({required this.kind, this.existing});

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _note = TextEditingController(text: widget.existing?.note);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final storeId = ref.read(activeStoreIdProvider);
    if (storeId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final dao = ref.read(contactDaoProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    final navigator = Navigator.of(context);
    final now = DateTime.now();
    try {
      final existing = widget.existing;
      final ContactRecord saved;
      if (existing == null) {
        saved = await dao.create(
          storeId: storeId,
          kind: widget.kind,
          name: _name.text,
          location: _location.text,
          phone: _phone.text,
          note: _note.text,
          now: now,
        );
      } else {
        await dao.update(
          existing.id,
          name: _name.text,
          location: _location.text,
          phone: _phone.text,
          note: _note.text,
          now: now,
        );
        saved = (await dao.findById(existing.id))!;
      }
      revision.bump();
      navigator.pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Belum tersimpan. Coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${isEdit ? 'Ubah' : 'Tambah'} ${widget.kind.label.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Lokasi (opsional)',
                hintText: widget.kind == ContactKind.pelanggan
                    ? 'Mis. Kampus, Kantor Kelurahan'
                    : 'Mis. Pasar Minggu',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telepon (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: widget.kind == ContactKind.supplier
                    ? 'Mis. pemasok ayam & telur'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
