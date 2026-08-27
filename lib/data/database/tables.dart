import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuidGenerator = Uuid();

/// Public because Drift emits client-default callbacks into the generated
/// database library, which imports this table library separately.
String newId() => _uuidGenerator.v4();

/// A local person known to this device: the app's own user, plus any
/// group members added by name (there is no server-side account system
/// — every "user" here is just a local record).
class Users extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Single-letter/initials avatar fallback, derived from name at
  /// creation time and stored so it stays stable even if display logic
  /// changes later.
  TextColumn get initials => text().withLength(min: 1, max: 2)();

  /// True only for the single record representing the device owner
  /// (created during onboarding). Used to distinguish "me" from other
  /// group members for balance/ownership displays.
  BoolColumn get isCurrentUser =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Groups extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Archiving preserves the group's financial history while keeping it out of
  /// the normal picker and list. It is deliberately not a cascading delete.
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Join table linking a Group to its member Users.
class GroupMembers extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

enum SplitTypeDb { equal, specificAmount, ratio }

class Expenses extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();

  /// Total amount, stored in integer paise. Never a REAL/double column —
  /// this is the whole point of representing money as paise: the
  /// database itself cannot introduce floating point error.
  IntColumn get totalAmountPaise => integer()();

  TextColumn get category => text().withLength(min: 1, max: 40)();

  TextColumn get splitType =>
      textEnum<SplitTypeDb>().withDefault(const Constant('equal'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Soft-delete flag. Deletion is implemented as a flag flip (not a
  /// physical DELETE) so that "swipe to delete -> Undo" can restore the
  /// expense, and everything downstream (balances, activity, analytics)
  /// simply filters on isDeleted = false.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// How much of an expense each participant is responsible for
/// (their computed share), regardless of how much they actually paid.
class ExpenseParticipants extends Table {
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  /// This participant's computed share of the total, in paise. The sum
  /// of amountOwedPaise across all participants of an expense must
  /// always equal totalAmountPaise exactly (enforced by the split
  /// engine before the row is written, not by a DB constraint, since
  /// Drift/SQLite has no portable "sum of sibling rows" check).
  IntColumn get amountOwedPaise => integer()();

  /// Ratio numerator used to produce amountOwedPaise, when the split
  /// type is ratio (e.g. 40 for 40%). Null for equal/specific splits.
  IntColumn get ratio => integer().nullable()();

  @override
  Set<Column> get primaryKey => {expenseId, userId};
}

/// How much each payer actually paid upfront for an expense. Supports
/// multiple payers per expense.
class ExpensePayments extends Table {
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPaidPaise => integer()();

  @override
  Set<Column> get primaryKey => {expenseId, userId};
}

enum SettlementStatus { pending, completed }

/// A recorded (optimized) repayment between two users within a group.
/// Rows are created when the user runs "Settle Up" and marks a suggested
/// transfer as paid; they are a record of settlement activity, not a
/// live-computed value.
class Settlements extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get fromUserId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get toUserId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPaise => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get status =>
      textEnum<SettlementStatus>().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table holding local app preferences (theme mode, and
/// onboarding completion). We model this as a table with a fixed id
/// rather than shared_preferences alone so it lives in the same
/// transactional store as everything else and is trivially watchable
/// with Drift streams if a screen ever needs to react to it.
class AppSettingsTable extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get themeMode =>
      text().withDefault(const Constant('system'))(); // light | dark | system
  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
