import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/app_database.dart';
import 'core/db/dao/settings_dao.dart';
import 'core/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await initializeDateFormatting('id_ID');

  final database = AppDatabase();
  await database.open();

  final onboardingDone = await SettingsDao(database.db)
      .getFlag(SettingsKeys.onboardingDone);

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: SmartTokoApp(onboardingDone: onboardingDone),
    ),
  );
}
