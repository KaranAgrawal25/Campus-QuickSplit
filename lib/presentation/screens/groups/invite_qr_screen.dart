import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class InviteQrScreen extends StatelessWidget {
  const InviteQrScreen({
    super.key,
    required this.groupName,
    required this.memberCount,
    required this.payload,
  });
  final String groupName, payload;
  final int memberCount;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Invite to $groupName')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: QrImageView(data: payload, size: 240),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Scan this code to join the group.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('$groupName · $memberCount members'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}
