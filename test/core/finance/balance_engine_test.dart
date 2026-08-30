import 'package:campus_quicksplit/core/finance/balance_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payer, shares, and settlements yield correct current-user balance', () {
    final positions = BalanceEngine.positions(
      expensePayments: const [
        BalanceTransfer(fromUserId: '', toUserId: 'me', amountPaise: 900),
      ],
      expenseShares: const [
        BalanceTransfer(fromUserId: 'me', toUserId: '', amountPaise: 300),
        BalanceTransfer(fromUserId: 'a', toUserId: '', amountPaise: 300),
        BalanceTransfer(fromUserId: 'b', toUserId: '', amountPaise: 300),
      ],
      settlements: const [
        BalanceTransfer(fromUserId: 'a', toUserId: 'me', amountPaise: 100),
      ],
    );
    final summary = BalanceEngine.currentUserSummary(positions, 'me');
    expect(summary.net, 500);
    expect(summary.owed, 500);
    expect(summary.owes, 0);
  });
  test('current user owing is reported as positive owe', () {
    final summary = BalanceEngine.currentUserSummary({'me': -250}, 'me');
    expect(summary.owes, 250);
    expect(summary.owed, 0);
  });

  test('multiple payers are balanced from actual contributions and shares', () {
    final positions = BalanceEngine.positions(
      expensePayments: const [
        BalanceTransfer(fromUserId: '', toUserId: 'karan', amountPaise: 200000),
        BalanceTransfer(fromUserId: '', toUserId: 'abhay', amountPaise: 100000),
        BalanceTransfer(fromUserId: '', toUserId: 'manav', amountPaise: 100000),
      ],
      expenseShares: const [
        BalanceTransfer(fromUserId: 'karan', toUserId: '', amountPaise: 100000),
        BalanceTransfer(fromUserId: 'abhay', toUserId: '', amountPaise: 100000),
        BalanceTransfer(fromUserId: 'manav', toUserId: '', amountPaise: 100000),
        BalanceTransfer(
          fromUserId: 'pranshu',
          toUserId: '',
          amountPaise: 100000,
        ),
      ],
      settlements: const [],
    );

    expect(positions, {
      'karan': 100000,
      'abhay': 0,
      'manav': 0,
      'pranshu': -100000,
    });
    expect(BalanceEngine.suggestedSettlements(positions), hasLength(1));
  });

  test('settlement suggestions are deterministic and conserve paise', () {
    final suggestions = BalanceEngine.suggestedSettlements({
      'karan-id': 200000,
      'pranshu-id': 50000,
      'iyer-id': -120000,
      'manav-id': -80000,
      'abhay-id': -50000,
      'zero-id': 0,
    });
    expect(suggestions, hasLength(3));
    expect(
      suggestions.fold<int>(0, (sum, item) => sum + item.amountPaise),
      250000,
    );
    expect(
      suggestions.every((item) => item.fromUserId != item.toUserId),
      isTrue,
    );
  });
}
