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
}
