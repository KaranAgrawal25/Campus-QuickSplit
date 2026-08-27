import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      children: [
        ListTile(
          title: const Text('Theme'),
          subtitle: const Text('Choose how Campus QuickSplit looks'),
          trailing: DropdownButton<String>(
            value:
                ref.watch(appSettingsProvider).valueOrNull?.themeMode ??
                'system',
            items: const [
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'light', child: Text('Light')),
              DropdownMenuItem(value: 'dark', child: Text('Dark')),
            ],
            onChanged: (value) {
              if (value != null) {
                (ref
                        .read(appDatabaseProvider)
                        .update(ref.read(appDatabaseProvider).appSettingsTable)
                      ..where((s) => s.id.equals(0)))
                    .write(AppSettingsTableCompanion(themeMode: Value(value)));
              }
            },
          ),
        ),
        const AboutListTile(
          applicationName: 'Campus QuickSplit',
          applicationVersion: '0.1.0',
          applicationLegalese: 'Local-first student expense splitting',
        ),
      ],
    ),
  );
}
