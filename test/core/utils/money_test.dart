import 'package:flutter_test/flutter_test.dart';
import 'package:campus_quicksplit/core/utils/money.dart';

void main() {
  group('Money basic arithmetic', () {
    test('fromRupees converts correctly', () {
      expect(Money.fromRupees(10).paise, 1000);
      expect(Money.fromRupees(10.5).paise, 1050);
      expect(Money.fromRupees(0.1).paise, 10);
    });

    test('addition and subtraction are exact', () {
      final a = Money.fromRupees(10.50);
      final b = Money.fromRupees(2.25);
      expect((a + b).paise, 1275);
      expect((a - b).paise, 825);
    });
  });

  group('Money.splitEqually', () {
    test('100 / 4 splits evenly with no remainder', () {
      final shares = Money.splitEqually(Money.fromRupees(100), 4);
      expect(shares, [
        Money.fromRupees(25),
        Money.fromRupees(25),
        Money.fromRupees(25),
        Money.fromRupees(25),
      ]);
      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum.paise, Money.fromRupees(100).paise);
    });

    test('1001 / 3 distributes the remainder and sums exactly', () {
      final shares = Money.splitEqually(Money.fromRupees(1001), 3);
      // Expect paise-level: 100100 / 3 = 33366 remainder 2
      // -> two shares get +1 paisa: 33367, 33367, 33366
      final paiseValues = shares.map((m) => m.paise).toList();
      expect(paiseValues, [33367, 33367, 33366]);

      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum.paise, 100100);
      expect(sum, Money.fromRupees(1001));

      // No share may differ from another by more than 1 paisa.
      final maxPaise = paiseValues.reduce((a, b) => a > b ? a : b);
      final minPaise = paiseValues.reduce((a, b) => a < b ? a : b);
      expect(maxPaise - minPaise, lessThanOrEqualTo(1));
    });

    test('999 / 7 sums exactly and stays within 1 paisa of each other', () {
      final shares = Money.splitEqually(Money.fromRupees(999), 7);
      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum, Money.fromRupees(999));

      final paiseValues = shares.map((m) => m.paise).toList();
      final maxPaise = paiseValues.reduce((a, b) => a > b ? a : b);
      final minPaise = paiseValues.reduce((a, b) => a < b ? a : b);
      expect(maxPaise - minPaise, lessThanOrEqualTo(1));
    });

    test('throws for zero or negative participant count', () {
      expect(
        () => Money.splitEqually(Money.fromRupees(100), 0),
        throwsArgumentError,
      );
      expect(
        () => Money.splitEqually(Money.fromRupees(100), -2),
        throwsArgumentError,
      );
    });
  });

  group('Money.splitByRatio', () {
    test('40/30/20/10 split of ₹1200 sums exactly', () {
      final shares = Money.splitByRatio(Money.fromRupees(1200), [
        40,
        30,
        20,
        10,
      ]);
      expect(shares, [
        Money.fromRupees(480),
        Money.fromRupees(360),
        Money.fromRupees(240),
        Money.fromRupees(120),
      ]);
      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum, Money.fromRupees(1200));
    });

    test('uneven ratio split still sums exactly (no rounding drift)', () {
      // ₹1001 split 40/30/20/10 does not divide evenly in paise.
      final shares = Money.splitByRatio(Money.fromRupees(1001), [
        40,
        30,
        20,
        10,
      ]);
      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum, Money.fromRupees(1001));
    });

    test('equal ratios behave like an equal split', () {
      final shares = Money.splitByRatio(Money.fromRupees(1001), [1, 1, 1]);
      final sum = shares.fold(const Money.zero(), (a, b) => a + b);
      expect(sum, Money.fromRupees(1001));
      final paiseValues = shares.map((m) => m.paise).toList()..sort();
      expect(paiseValues, [33366, 33367, 33367]);
    });

    test('throws for empty ratio list', () {
      expect(
        () => Money.splitByRatio(Money.fromRupees(100), []),
        throwsArgumentError,
      );
    });
  });

  group('Money formatting', () {
    test('formats with rupee symbol and grouping', () {
      expect(Money.fromRupees(1234.50).format(), '₹1,234.50');
    });

    test('formatCompact drops trailing .00', () {
      expect(Money.fromRupees(200).formatCompact(), '₹200');
      expect(Money.fromRupees(200.50).formatCompact(), '₹200.50');
    });
  });
}
