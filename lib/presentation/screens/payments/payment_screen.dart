import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/payments/upi_payment.dart';
import '../../../core/utils/money.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/balance_repository.dart';
import '../../providers/dashboard_providers.dart';

/// Payment assistance only: an external UPI app or QR can be used to pay, but
/// the settlement is recorded only after this user explicitly confirms it.
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({
    super.key,
    required this.recipient,
    required this.suggestion,
  });

  final User recipient;
  final GroupSettlementSuggestion suggestion;

  UpiPayment? _paymentOrNull() {
    final upiId = recipient.upiId?.trim();
    if (upiId == null || upiId.isEmpty || !UpiPayment.isValidUpiId(upiId)) {
      return null;
    }
    try {
      final payment = UpiPayment(
        payeeUpiId: upiId,
        payeeName: recipient.name,
        amountPaise: suggestion.amountPaise,
        note: 'Campus QuickSplit settlement',
      );
      payment.validate();
      return payment;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _openUpiApp(BuildContext context, UpiPayment payment) async {
    try {
      final uri = payment.toUri();
      if (!await canLaunchUrl(uri)) {
        if (context.mounted) _showNoUpiApp(context);
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) _showNoUpiApp(context);
    } catch (_) {
      if (context.mounted) _showNoUpiApp(context);
    }
  }

  void _showNoUpiApp(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No UPI app found. You can use the QR option or manually mark the payment after paying elsewhere.',
        ),
      ),
    );
  }

  Future<bool> _confirmAndRecord(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Did you complete the payment?'),
        content: Text(
          '${Money(suggestion.amountPaise).formatCompact()} to ${recipient.name}\n\n'
          'Campus QuickSplit cannot verify payments. Only continue if you paid externally.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, I Paid'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!context.mounted) return false;
    try {
      await ref
          .read(balanceRepositoryProvider)
          .recordSuggestedSettlement(
            groupId: suggestion.groupId,
            fromUserId: suggestion.fromUserId,
            toUserId: suggestion.toUserId,
            amountPaise: suggestion.amountPaise,
            note: 'Marked paid via UPI assistance',
          );
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not record the settlement. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = _paymentOrNull();
    final hasUpi = payment != null;
    return Scaffold(
      appBar: AppBar(title: Text('Pay ${recipient.name}')),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppConstants.spaceXs),
                  Text(
                    Money(suggestion.amountPaise).formatCompact(),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppConstants.spaceLg),
                  Text('UPI ID', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppConstants.spaceXs),
                  Text(
                    recipient.upiId?.trim().isNotEmpty == true
                        ? recipient.upiId!.trim()
                        : 'UPI ID not available',
                  ),
                  if (!hasUpi) ...[
                    const SizedBox(height: AppConstants.spaceSm),
                    Text(
                      recipient.upiId?.trim().isNotEmpty == true
                          ? 'Invalid UPI ID. Ask ${recipient.name} to update their UPI ID.'
                          : '${recipient.name} needs to add a UPI ID before you can create a payment request.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLg),
          Text(
            'Choose payment method',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppConstants.spaceSm),
          FilledButton.icon(
            onPressed: hasUpi ? () => _openUpiApp(context, payment) : null,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open UPI App'),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          OutlinedButton.icon(
            onPressed: hasUpi
                ? () async {
                    final recorded = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _UpiQrScreen(
                          recipient: recipient,
                          suggestion: suggestion,
                          payment: payment,
                        ),
                      ),
                    );
                    if (recorded == true && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  }
                : null,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Show UPI QR'),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          TextButton(
            onPressed: hasUpi
                ? () async {
                    if (await _confirmAndRecord(context, ref) &&
                        context.mounted) {
                      Navigator.pop(context, true);
                    }
                  }
                : null,
            child: const Text('Mark as Paid'),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          const Text(
            'Mark as Paid records your confirmation. It does not verify a bank or UPI transaction.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _UpiQrScreen extends ConsumerWidget {
  const _UpiQrScreen({
    required this.recipient,
    required this.suggestion,
    required this.payment,
  });

  final User recipient;
  final GroupSettlementSuggestion suggestion;
  final UpiPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Pay ${recipient.name}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Money(suggestion.amountPaise).formatCompact(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceLg),
                  child: QrImageView(
                    data: payment.toUri().toString(),
                    size: 240,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              const Text(
                'Scan this QR using any supported UPI app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spaceLg),
              FilledButton(
                onPressed: () async {
                  final completed = await PaymentScreen(
                    recipient: recipient,
                    suggestion: suggestion,
                  )._confirmAndRecord(context, ref);
                  if (completed && context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('I Have Paid'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
