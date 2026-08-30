/// Pure, paise-only split calculations and validation.
class SplitShare {
  const SplitShare({
    required this.userId,
    required this.amountPaise,
    this.ratio,
  });

  final String userId;
  final int amountPaise;
  final int? ratio;
}

class SplitEngine {
  SplitEngine._();

  static List<SplitShare> equal({
    required int totalPaise,
    required List<String> userIds,
  }) {
    _validateInputs(totalPaise, userIds);
    final base = totalPaise ~/ userIds.length;
    final remainder = totalPaise % userIds.length;
    return List.generate(
      userIds.length,
      (index) => SplitShare(
        userId: userIds[index],
        amountPaise: base + (index < remainder ? 1 : 0),
      ),
    );
  }

  static List<SplitShare> ratio({
    required int totalPaise,
    required List<String> userIds,
    required List<int> ratios,
  }) {
    _validateInputs(totalPaise, userIds);
    if (ratios.length != userIds.length ||
        ratios.any((ratio) => ratio < 0) ||
        ratios.every((ratio) => ratio == 0)) {
      throw ArgumentError(
        'Ratios must be non-negative with one positive value',
      );
    }
    final sum = ratios.fold<int>(0, (value, ratio) => value + ratio);
    final amounts = List<int>.filled(userIds.length, 0);
    final remainders = List<int>.filled(userIds.length, 0);
    var allocated = 0;
    for (var index = 0; index < userIds.length; index++) {
      final product = totalPaise * ratios[index];
      amounts[index] = product ~/ sum;
      remainders[index] = product % sum;
      allocated += amounts[index];
    }
    final order = List.generate(userIds.length, (index) => index)
      ..sort((a, b) {
        final comparison = remainders[b].compareTo(remainders[a]);
        return comparison == 0 ? a.compareTo(b) : comparison;
      });
    for (var i = 0; i < totalPaise - allocated; i++) {
      amounts[order[i]]++;
    }
    return List.generate(
      userIds.length,
      (index) => SplitShare(
        userId: userIds[index],
        amountPaise: amounts[index],
        ratio: ratios[index],
      ),
    );
  }

  /// Applies whole-number percentage allocations. Percentages must total
  /// exactly 100; allocation then uses the same deterministic paise remainder
  /// distribution as [ratio].
  static List<SplitShare> percentage({
    required int totalPaise,
    required List<String> userIds,
    required List<int> percentages,
  }) {
    _validateInputs(totalPaise, userIds);
    if (percentages.length != userIds.length ||
        percentages.any((percentage) => percentage < 0) ||
        percentages.fold<int>(0, (sum, percentage) => sum + percentage) !=
            100) {
      throw ArgumentError('Percentages must be non-negative and total 100');
    }
    if (percentages.every((percentage) => percentage == 0)) {
      throw ArgumentError('At least one percentage must be positive');
    }
    return ratio(totalPaise: totalPaise, userIds: userIds, ratios: percentages);
  }

  static List<SplitShare> custom({
    required int totalPaise,
    required List<SplitShare> shares,
  }) {
    if (totalPaise <= 0 || shares.isEmpty) {
      throw ArgumentError('Amount must be positive and have participants');
    }
    if (shares.any((share) => share.amountPaise <= 0)) {
      throw ArgumentError('Custom amounts must be positive');
    }
    if (shares.map((share) => share.userId).toSet().length != shares.length) {
      throw ArgumentError('A participant can only appear once');
    }
    final sum = shares.fold<int>(
      0,
      (value, share) => value + share.amountPaise,
    );
    if (sum != totalPaise) {
      throw ArgumentError('Custom shares must equal the expense total');
    }
    return shares;
  }

  static void _validateInputs(int totalPaise, List<String> userIds) {
    if (totalPaise <= 0 ||
        userIds.isEmpty ||
        userIds.toSet().length != userIds.length) {
      throw ArgumentError('Amount must be positive with unique participants');
    }
  }
}
