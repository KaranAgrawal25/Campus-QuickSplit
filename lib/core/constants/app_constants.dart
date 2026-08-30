/// Central place for values that must stay consistent across the app
/// (e.g. the same category list used by the expense form AND analytics
/// grouping — if these ever diverge, analytics silently breaks).
class AppConstants {
  AppConstants._();

  static const String appName = 'Campus QuickSplit';
  static const String tagline =
      'Split expenses. Settle smarter. Works offline.';

  static const List<String> expenseCategories = [
    'Food',
    'Transport',
    'Rent',
    'Hotel',
    'Education',
    'Shopping',
    'Subscriptions',
    'Entertainment',
    'Utilities',
    'Medical',
    'Travel',
    'Other',
  ];

  /// Consistent spacing scale used across the design system instead of
  /// ad-hoc magic numbers in every widget.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static const double radiusMd = 16;
  static const double radiusLg = 24;
}
