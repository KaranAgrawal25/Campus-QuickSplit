import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/expense_repository.dart';
import 'database_provider.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(appDatabaseProvider)),
);
final recentExpensesProvider = StreamProvider<List<Expense>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchRecent(),
);
final groupExpensesProvider = StreamProvider.family<List<Expense>, String>(
  (ref, id) => ref.watch(expenseRepositoryProvider).watchRecent(groupId: id),
);
