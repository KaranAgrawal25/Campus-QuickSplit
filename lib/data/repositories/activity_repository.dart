import '../database/app_database.dart';

enum ActivityKind { expense, settlement }

class ActivityEntry {
  const ActivityEntry.expense(
    this.expense, {
    required this.groupName,
    required this.actorName,
    this.memberNames = const [],
  }) : kind = ActivityKind.expense,
       settlement = null;
  const ActivityEntry.settlement(
    this.settlement, {
    required this.groupName,
    required this.actorName,
    this.memberNames = const [],
  }) : kind = ActivityKind.settlement,
       expense = null;

  final ActivityKind kind;
  final Expense? expense;
  final Settlement? settlement;
  final String groupName;
  final String actorName;
  final List<String> memberNames;
  DateTime get occurredAt => expense?.createdAt ?? settlement!.createdAt;
  String get contextLabel => expense == null
      ? '$actorName · $groupName'
      : '${expense!.category} · $actorName paid · $groupName';
  String get searchableText =>
      '${expense?.title ?? 'settlement'} ${expense?.category ?? ''} $groupName $actorName ${memberNames.join(' ')} ${expense?.totalAmountPaise ?? settlement?.amountPaise ?? ''}';
}

class ActivityRepository {
  ActivityRepository(this._db);
  final AppDatabase _db;

  Stream<List<ActivityEntry>> watchRecent() async* {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.expenses,
            _db.settlements,
            _db.expensePayments,
            _db.groupMembers,
            _db.groups,
            _db.users,
          },
        )
        .watch();
    await for (final _ in trigger) {
      final expenses = await (_db.select(
        _db.expenses,
      )..where((expense) => expense.isDeleted.equals(false))).get();
      final settlements = await _db.select(_db.settlements).get();
      final groups = await _db.select(_db.groups).get();
      final users = await _db.select(_db.users).get();
      final payments = await _db.select(_db.expensePayments).get();
      final memberships = await _db.select(_db.groupMembers).get();
      final groupNames = {for (final group in groups) group.id: group.name};
      final userNames = {for (final user in users) user.id: user.name};
      final firstPayerByExpense = <String, String>{
        for (final payment in payments)
          payment.expenseId: userNames[payment.userId] ?? 'Unknown member',
      };
      final membersByGroup = <String, List<String>>{};
      for (final membership in memberships) {
        membersByGroup
            .putIfAbsent(membership.groupId, () => [])
            .add(userNames[membership.userId] ?? '');
      }
      final result = <ActivityEntry>[
        ...expenses.map(
          (expense) => ActivityEntry.expense(
            expense,
            groupName: groupNames[expense.groupId] ?? 'Unknown group',
            actorName: firstPayerByExpense[expense.id] ?? 'Unknown member',
            memberNames: membersByGroup[expense.groupId] ?? const [],
          ),
        ),
        ...settlements.map(
          (settlement) => ActivityEntry.settlement(
            settlement,
            groupName: groupNames[settlement.groupId] ?? 'Unknown group',
            actorName: userNames[settlement.fromUserId] ?? 'Unknown member',
            memberNames: membersByGroup[settlement.groupId] ?? const [],
          ),
        ),
      ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      yield result;
    }
  }
}
