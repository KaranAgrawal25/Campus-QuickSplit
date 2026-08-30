import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/app.dart';
import 'core/sync/cloud_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CloudRuntime.initialize();
  runApp(const ProviderScope(child: CampusQuickSplitApp()));
}
