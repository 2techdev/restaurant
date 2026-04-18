/// Entry point for the GastroCore Boss app (owner mobile dashboard).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/boss_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise date symbols for the locales the Boss app supports so
  // `DateFormat('dd MMMM yyyy', 'tr')` etc. work without throwing.
  await initializeDateFormatting('tr');
  await initializeDateFormatting('de');

  runApp(
    const ProviderScope(
      child: BossApp(),
    ),
  );
}
