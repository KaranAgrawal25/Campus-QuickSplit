import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/money.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'balance_repository.dart';

class ReminderDraft {
  const ReminderDraft({
    required this.title,
    required this.body,
    required this.frequency,
    required this.scheduledAt,
    this.weekday,
    this.dayOfMonth,
  });
  final String title, body;
  final ReminderFrequency frequency;
  final DateTime scheduledAt;
  final int? weekday, dayOfMonth;
}

/// Durable, on-device notification schedules. Calendar components are passed
/// to the OS, so daily, weekly, and monthly reminders repeat while the app is
/// closed; no server or fake background loop is involved.
class ReminderRepository {
  ReminderRepository(this._db, {FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final AppDatabase _db;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Stream<List<ReminderSchedule>> watchSchedules() {
    final query = _db.select(_db.reminderSchedules)
      ..orderBy([(row) => OrderingTerm.asc(row.nextScheduledAt)]);
    return query.watch();
  }

  Future<ReminderSchedule> create(ReminderDraft draft) async {
    _validate(draft);
    await _initialize();
    final id = newId();
    final next = _next(draft, DateTime.now());
    await _schedule(id, draft, next);
    return _db
        .into(_db.reminderSchedules)
        .insertReturning(
          ReminderSchedulesCompanion.insert(
            id: Value(id),
            title: draft.title.trim(),
            body: draft.body.trim(),
            frequency: draft.frequency,
            hour: draft.scheduledAt.hour,
            minute: draft.scheduledAt.minute,
            weekday: Value(draft.weekday),
            dayOfMonth: Value(draft.dayOfMonth),
            scheduledAt: draft.scheduledAt,
            nextScheduledAt: next,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setEnabled(ReminderSchedule schedule, bool enabled) async {
    await _initialize();
    var next = schedule.nextScheduledAt;
    if (!enabled) {
      await _plugin.cancel(id: _notificationId(schedule.id));
    } else {
      final draft = _from(schedule);
      next = _next(draft, DateTime.now());
      await _schedule(schedule.id, draft, next);
    }
    await (_db.update(
      _db.reminderSchedules,
    )..where((row) => row.id.equals(schedule.id))).write(
      ReminderSchedulesCompanion(
        isEnabled: Value(enabled),
        nextScheduledAt: Value(next),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> update(String id, ReminderDraft draft) async {
    _validate(draft);
    await _initialize();
    final next = _next(draft, DateTime.now());
    await _plugin.cancel(id: _notificationId(id));
    await _schedule(id, draft, next);
    await (_db.update(
      _db.reminderSchedules,
    )..where((row) => row.id.equals(id))).write(
      ReminderSchedulesCompanion(
        title: Value(draft.title.trim()),
        body: Value(draft.body.trim()),
        frequency: Value(draft.frequency),
        hour: Value(draft.scheduledAt.hour),
        minute: Value(draft.scheduledAt.minute),
        weekday: Value(draft.weekday),
        dayOfMonth: Value(draft.dayOfMonth),
        scheduledAt: Value(draft.scheduledAt),
        nextScheduledAt: Value(next),
        isEnabled: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await _initialize();
    await _plugin.cancel(id: _notificationId(id));
    await (_db.delete(
      _db.reminderSchedules,
    )..where((row) => row.id.equals(id))).go();
  }

  /// Re-registers persisted schedules after backup/cloud restore or an OS
  /// reboot. Repeating notifications are safe to schedule again because they
  /// use a stable notification id; stale one-time reminders are disabled.
  Future<void> restoreScheduledNotifications() async {
    final enabled = await (_db.select(
      _db.reminderSchedules,
    )..where((row) => row.isEnabled.equals(true))).get();
    if (enabled.isEmpty) return;
    await _initialize();
    final now = DateTime.now();
    for (final schedule in enabled) {
      final draft = _from(schedule);
      if (schedule.frequency == ReminderFrequency.once &&
          !schedule.scheduledAt.isAfter(now)) {
        await (_db.update(
          _db.reminderSchedules,
        )..where((row) => row.id.equals(schedule.id))).write(
          ReminderSchedulesCompanion(
            isEnabled: const Value(false),
            updatedAt: Value(now),
          ),
        );
        continue;
      }
      final next = schedule.frequency == ReminderFrequency.once
          ? schedule.scheduledAt
          : _next(draft, now);
      await _schedule(schedule.id, draft, next);
      await (_db.update(_db.reminderSchedules)
            ..where((row) => row.id.equals(schedule.id)))
          .write(ReminderSchedulesCompanion(nextScheduledAt: Value(next)));
    }
  }

  Future<void> sendBalanceReminder(BalanceSummary summary) async {
    await _initialize();
    final message = summary.netBalancePaise == 0
        ? 'You are settled up across your active groups.'
        : summary.netBalancePaise > 0
        ? 'You are owed ${Money(summary.youAreOwedPaise).formatCompact()} across active groups.'
        : 'You owe ${Money(summary.youOwePaise).formatCompact()} across active groups.';
    await _plugin.show(
      id: 1001,
      title: 'Campus QuickSplit balance',
      body: message,
      notificationDetails: _details,
    );
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.requestNotificationsPermission() == false) {
      throw StateError('Notifications are not permitted on this device');
    }
    _initialized = true;
  }

  Future<void> _schedule(String id, ReminderDraft draft, DateTime next) =>
      _plugin.zonedSchedule(
        id: _notificationId(id),
        title: draft.title.trim(),
        body: draft.body.trim(),
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: switch (draft.frequency) {
          ReminderFrequency.once => null,
          ReminderFrequency.daily => DateTimeComponents.time,
          ReminderFrequency.weekly => DateTimeComponents.dayOfWeekAndTime,
          ReminderFrequency.monthly => DateTimeComponents.dayOfMonthAndTime,
        },
      );

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'balance_reminders',
      'Balance reminders',
      channelDescription: 'User-requested expense balance reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  void _validate(ReminderDraft draft) {
    if (draft.title.trim().isEmpty || draft.body.trim().isEmpty) {
      throw ArgumentError('Enter a reminder title and message');
    }
    if (draft.frequency == ReminderFrequency.weekly &&
        (draft.weekday == null || draft.weekday! < 1 || draft.weekday! > 7)) {
      throw ArgumentError('Choose a valid day of the week');
    }
    if (draft.frequency == ReminderFrequency.monthly &&
        (draft.dayOfMonth == null ||
            draft.dayOfMonth! < 1 ||
            draft.dayOfMonth! > 31)) {
      throw ArgumentError('Choose a valid day of the month');
    }
  }

  ReminderDraft _from(ReminderSchedule schedule) => ReminderDraft(
    title: schedule.title,
    body: schedule.body,
    frequency: schedule.frequency,
    scheduledAt: schedule.scheduledAt,
    weekday: schedule.weekday,
    dayOfMonth: schedule.dayOfMonth,
  );

  DateTime _next(ReminderDraft draft, DateTime now) {
    DateTime at(int year, int month, int day) => DateTime(
      year,
      month,
      day,
      draft.scheduledAt.hour,
      draft.scheduledAt.minute,
    );
    final local = now.toLocal();
    switch (draft.frequency) {
      case ReminderFrequency.once:
        if (!draft.scheduledAt.isAfter(now)) {
          throw ArgumentError('Choose a time in the future');
        }
        return draft.scheduledAt;
      case ReminderFrequency.daily:
        final candidate = at(local.year, local.month, local.day);
        return candidate.isAfter(local)
            ? candidate
            : candidate.add(const Duration(days: 1));
      case ReminderFrequency.weekly:
        final offset = (draft.weekday! - local.weekday + 7) % 7;
        final candidate = at(
          local.year,
          local.month,
          local.day,
        ).add(Duration(days: offset));
        return candidate.isAfter(local)
            ? candidate
            : candidate.add(const Duration(days: 7));
      case ReminderFrequency.monthly:
        DateTime candidate(int year, int month) {
          final lastDay = DateTime(year, month + 1, 0).day;
          return at(
            year,
            month,
            draft.dayOfMonth! > lastDay ? lastDay : draft.dayOfMonth!,
          );
        }
        final thisMonth = candidate(local.year, local.month);
        return thisMonth.isAfter(local)
            ? thisMonth
            : candidate(local.year, local.month + 1);
    }
  }

  int _notificationId(String id) => id.hashCode & 0x7fffffff;
}
