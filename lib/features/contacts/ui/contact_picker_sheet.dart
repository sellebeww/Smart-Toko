/// Pemilih pelanggan/supplier dari layar konfirmasi transaksi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/dao/contact_dao.dart';
import '../../transactions/ui/confirmation_sheet.dart';
import '../contacts_providers.dart';
import 'contact_form_sheet.dart';

Future<PickedContact?> showContactPicker(
  BuildContext context,
  ContactKind kind,
) {
  return showModalBottomSheet<PickedContact>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ContactPicker(kind: kind),
  );
}

class _ContactPicker extends ConsumerStatefulWidget {
  final ContactKind kind;

  const _ContactPicker({required this.kind});

  @override
  ConsumerState<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends ConsumerState<_ContactPicker> {
  String _query = '';

  Future<void> _addNew() async {
    final navigator = Navigator.of(context);
    final created = await showContactForm(context, kind: widget.kind);
    if (created != null) navigator.pop((id: created.id, name: created.name));
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider(widget.kind));
    final q = _query.trim().toLowerCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pilih ${widget.kind.label.toLowerCase()}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addNew,
                  icon: const Icon(Icons.add),
                  label: const Text('Baru'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari nama atau lokasi',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: contacts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (all) {
                final shown = q.isEmpty
                    ? all
                    : all
                          .where(
                            (c) =>
                                c.name.toLowerCase().contains(q) ||
                                (c.location?.toLowerCase().contains(q) ??
                                    false),
                          )
                          .toList();
                if (shown.isEmpty) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: _addNew,
                      icon: const Icon(Icons.add),
                      label: Text(
                        all.isEmpty
                            ? 'Belum ada ${widget.kind.label.toLowerCase()}. Tambah'
                            : 'Tidak ketemu. Tambah baru',
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: c.location == null ? null : Text(c.location!),
                      onTap: () =>
                          Navigator.of(context).pop((id: c.id, name: c.name)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
