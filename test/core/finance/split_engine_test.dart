import 'package:campus_quicksplit/core/finance/split_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplitEngine equal', () {
    test('1001 / 3 is exact', () {
      final shares = SplitEngine.equal(
        totalPaise: 1001,
        userIds: ['a', 'b', 'c'],
      );
      expect(shares.map((s) => s.amountPaise), [334, 334, 333]);
    });
    test('999 / 7, 100 / 3, and 1 / 3 remain exact', () {
      for (final amount in [999, 100, 1]) {
        final shares = SplitEngine.equal(
          totalPaise: amount,
          userIds: [
            'a',
            'b',
            'c',
            if (amount == 999) ...['d', 'e', 'f', 'g'],
          ],
        );
        expect(shares.fold<int>(0, (sum, s) => sum + s.amountPaise), amount);
      }
    });
  });
  group('SplitEngine ratio', () {
    test('100 uses 1:2:3 exactly', () {
      final shares = SplitEngine.ratio(
        totalPaise: 100,
        userIds: ['a', 'b', 'c'],
        ratios: [1, 2, 3],
      );
      expect(shares.map((s) => s.amountPaise), [17, 33, 50]);
    });
    test('remainder distribution is deterministic', () {
      final shares = SplitEngine.ratio(
        totalPaise: 10,
        userIds: ['a', 'b', 'c'],
        ratios: [1, 1, 1],
      );
      expect(shares.map((s) => s.amountPaise), [4, 3, 3]);
    });
  });
  group('SplitEngine custom', () {
    test(
      'accepts exact positive sum',
      () => expect(
        SplitEngine.custom(
          totalPaise: 100,
          shares: const [
            SplitShare(userId: 'a', amountPaise: 40),
            SplitShare(userId: 'b', amountPaise: 60),
          ],
        ).length,
        2,
      ),
    );
    test('rejects invalid sums and non-positive values', () {
      expect(
        () => SplitEngine.custom(
          totalPaise: 100,
          shares: const [SplitShare(userId: 'a', amountPaise: 99)],
        ),
        throwsArgumentError,
      );
      expect(
        () => SplitEngine.custom(
          totalPaise: 100,
          shares: const [
            SplitShare(userId: 'a', amountPaise: 0),
            SplitShare(userId: 'b', amountPaise: 100),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
