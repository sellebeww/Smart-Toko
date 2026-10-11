/// Bagian "Pengingat" di Pengaturan, dan tawaran sekali di beranda.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reminder_planner.dart';
import '../reminder_providers.dart';

const String permissionDeniedMessage =
    'Izin notifikasi belum diberikan. Nyalakan lewat Pengaturan HP > '
    'Aplikasi > SmartToko > Notifikasi, lalu coba lagi.';

Future<void> _apply(
  BuildContext context,
  WidgetRef ref,
  ReminderSettings next,
  ReminderSettings current,
) async {
  final controller = ref.read(reminderSettingsProvider.notifier);
  // Izin hanya diminta saat ada pengingat yang baru dinyalakan.
  final turningOn =
      (next.dailyEnabled && !current.dailyEnabled) ||
      (next.dueEnabled && !current.dueEnabled);
  final ok = turningOn ? await controller.enable(next) : true;
  if (!turningOn) await controller.save(next);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(permissionDeniedMessage)));
  }
}

class ReminderSettingsTiles extends ConsumerWidget {
  const ReminderSettingsTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(reminderSettingsProvider).value ?? const ReminderSettings();
    return Column(
      children: [
        SwitchListTile(
          value: settings.dailyEnabled,
          onChanged: (v) => _apply(
            context,
            ref,
            settings.copyWith(dailyEnabled: v),
            settings,
          ),
          title: const Text('Ingatkan mencatat tiap hari'),
          subtitle: Text(
            'Pukul ${settings.timeLabel}. Dilewati bila hari itu sudah ada '
            'catatan.',
          ),
        ),
        if (settings.dailyEnabled)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Jam pengingat'),
            trailing: Text(settings.timeLabel),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: settings.hour,
                  minute: settings.minute,
                ),
                helpText: 'Jam pengingat mencatat',
              );
              if (picked == null || !context.mounted) return;
              await _apply(
                context,
                ref,
                settings.copyWith(hour: picked.hour, minute: picked.minute),
                settings,
              );
            },
          ),
        SwitchListTile(
          value: settings.dueEnabled,
          onChanged: (v) =>
              _apply(context, ref, settings.copyWith(dueEnabled: v), settings),
          title: const Text('Ingatkan jatuh tempo kasbon'),
          subtitle: const Text(
            'Pagi pukul 08.00 bila ada kasbon yang jatuh tempo hari itu, '
            'atau yang sudah telat.',
          ),
        ),
      ],
    );
  }
}

/// Tawaran di beranda. Muncul sekali setelah ada catatan pertama.
class ReminderOfferCard extends ConsumerWidget {
  const ReminderOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(reminderOfferProvider).value ?? false;
    if (!show) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final current =
        ref.watch(reminderSettingsProvider).value ?? const ReminderSettings();
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mau diingatkan?',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Pengingat mencatat tiap pukul 20.00 (dilewati bila sudah '
              'mencatat), dan pengingat pagi saat ada kasbon jatuh tempo.',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(reminderSettingsProvider.notifier).save(current),
                  child: const Text('Tidak usah'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _apply(
                    context,
                    ref,
                    current.copyWith(dailyEnabled: true, dueEnabled: true),
                    current,
                  ),
                  child: const Text('Nyalakan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
