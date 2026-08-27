import 'package:intl/intl.dart';

/// Represents an amount of money as an exact integer number of paise
/// (1 rupee = 100 paise). We NEVER use double for money anywhere in the
/// app — floating point cannot represent amounts like ₹0.10 exactly, and
/// repeated arithmetic on doubles silently drifts (e.g. 1001/3 * 3 may
/// not equal 1001 in double arithmetic). Every rupee amount that touches
/// the database, the split engine, or the balance/settlement engines
/// flows through this type instead.
class Money implements Comparable<Money> {
  /// The exact amount, in paise. Always an integer.
  final int paise;

  const Money(this.paise);

  const Money.zero() : paise = 0;

  /// Constructs a Money from a rupee value that already has no
  /// sub-paise precision issues (e.g. parsed from user input as a
  /// decimal string with at most 2 decimal places).
  factory Money.fromRupees(num rupees) {
    // Round to the nearest paise to guard against binary floating point
    // representation error in the input itself (e.g. 19.9 -> 1989.999...).
    return Money((rupees * 100).round());
  }

  double get rupees => paise / 100.0;

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  Money operator -() => Money(-paise);

  bool get isZero => paise == 0;
  bool get isPositive => paise > 0;
  bool get isNegative => paise < 0;

  Money abs() => Money(paise.abs());

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Formats as "₹1,234.50". Uses en_IN grouping (lakh/crore commas).
  String format() => _inr.format(rupees);

  /// Formats without trailing ".00" when the amount is a whole rupee
  /// value, e.g. "₹200" instead of "₹200.00". Used in compact UI like
  /// dashboard summary chips.
  String formatCompact() {
    if (paise % 100 == 0) {
      final wholeRupees = NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      );
      return wholeRupees.format(rupees);
    }
    return format();
  }

  @override
  String toString() => format();

  /// Splits [total] into [count] shares that are as equal as possible
  /// and whose sum is *exactly* [total] (no rounding drift).
  ///
  /// Algorithm: integer-divide to get a base share for everyone, then
  /// distribute the leftover paise (total.paise % count) one paisa at a
  /// time to the first `remainder` shares. This is the standard
  /// "largest remainder" approach applied to an already-integer unit
  /// (paise), so there is no floating point involved at all.
  ///
  /// Example: ₹1001 split 3 ways -> [333.67, 333.67, 333.66] (in paise:
  /// [33367, 33367, 33366]), which sums to exactly 100100 paise.
  static List<Money> splitEqually(Money total, int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be greater than zero');
    }
    final base = total.paise ~/ count;
    final remainder = total.paise % count;
    return List<Money>.generate(
      count,
      (i) => Money(base + (i < remainder ? 1 : 0)),
    );
  }

  /// Splits [total] according to integer [ratios] (e.g. [40, 30, 20, 10]
  /// for 40%/30%/20%/10%). Ratios need not sum to 100 — they are treated
  /// as relative weights — but the caller (RatioSplitStrategy) enforces
  /// that percentages sum to exactly 100 before calling this, per the
  /// product's validation rule. Uses the same remainder-distribution
  /// technique as [splitEqually] so the shares always sum to exactly
  /// [total], regardless of rounding.
  static List<Money> splitByRatio(Money total, List<int> ratios) {
    if (ratios.isEmpty) {
      throw ArgumentError.value(ratios, 'ratios', 'must not be empty');
    }
    final ratioSum = ratios.fold<int>(0, (a, b) => a + b);
    if (ratioSum <= 0) {
      throw ArgumentError.value(ratios, 'ratios', 'must sum to more than zero');
    }

    // Compute each share's exact rational value or expressed as
    // floor(total * ratio / ratioSum), then distribute the leftover
    // paise (caused by integer division) to the shares with the
    // largest fractional remainder first. This guarantees the sum is
    // exactly total.paise and that rounding is distributed fairly
    // rather than always favoring the first or last participant.
    final n = ratios.length;
    final floors = List<int>.filled(n, 0);
    final remainders = List<int>.filled(n, 0);
    var allocated = 0;

    for (var i = 0; i < n; i++) {
      final product = total.paise * ratios[i];
      floors[i] = product ~/ ratioSum;
      remainders[i] = product % ratioSum;
      allocated += floors[i];
    }

    var leftover = total.paise - allocated;

    // Order indices by largest remainder first; ties broken by original
    // index for determinism.
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final cmp = remainders[b].compareTo(remainders[a]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    final result = List<int>.from(floors);
    for (final idx in order) {
      if (leftover <= 0) break;
      result[idx] += 1;
      leftover -= 1;
    }

    return result.map(Money.new).toList();
  }
}
