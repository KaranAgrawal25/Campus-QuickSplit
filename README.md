# Campus QuickSplit

**Campus QuickSplit — Frictionless Local-First Peer Expense Tracker**

Campus QuickSplit is a Flutter app for students, flatmates, friends, and
project teams who share expenses. It keeps the ledger on-device first, makes
split calculations exact, and provides optional Firebase-backed synchronization
for signed-in users.

## The problem

Shared spending is easy to make and tedious to reconcile. A group needs to
handle unequal contributions, custom shares, and multiple expenses without
leaving members to calculate a web of repayments by hand.

## What it does

- Creates groups and manages members.
- Records expenses with equal, ratio-based, and specific-value splits.
- Supports multiple contributors/payers when recording an expense.
- Stores money as integer paise to avoid floating-point rounding errors.
- Calculates balances and suggests a reduced, deterministic set of settlement
  transfers.
- Records settlements and maintains an activity history.
- Provides analytics, CSV expense export, and local JSON backup/restore.
- Supports recurring-expense templates and locally scheduled reminders.
- Offers light, dark, and system theme modes.
- Starts UPI payment flows or displays a UPI QR code, while requiring explicit
  user confirmation before recording a settlement. It does not verify bank or
  UPI payments.
- Remains usable offline: Drift/SQLite is the source of truth.
- Optionally syncs a durable operation outbox with Firebase after email/password
  sign-in, including Cloud Functions-authorized QR group invitations.

Google Sign-In is listed as a dependency but is not currently wired into the
application; Firebase authentication presently uses email/password flows.

## Architecture

```text
Presentation (Flutter screens and Riverpod providers)
        ↓
Repositories
        ↓
Drift / SQLite local database
        ↓
Optional Firebase Auth, Firestore, and Cloud Functions sync transport
```

- `lib/core/` — money, split/balance, invitation, payment, and cloud-runtime
  utilities
- `lib/data/` — Drift schema, migrations, and repositories
- `lib/presentation/` — app shell, providers, screens, and widgets
- `functions/` — trusted Firebase Functions for QR-invitation creation/joining
- `firestore.rules` — Firestore access-control rules
- `test/` — unit, persistence/migration, repository, and widget tests

## Requirements

- Flutter **3.44.0 or later**
- Dart SDK **3.12.0 or later**
- Android toolchain for Android builds
- macOS/Xcode toolchain for macOS builds
- Node.js and npm only when building or deploying Firebase Functions

The repository currently includes Android and macOS platform projects. It does
not include an iOS platform project.

## Run locally

```bash
flutter pub get
flutter run
```

Run the checks and tests:

```bash
flutter analyze
flutter test
```

Build a debug APK:

```bash
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk` and is not
committed to Git.

## Firebase (optional cloud sync)

Local expense tracking does not require Firebase. To enable authenticated cloud
sync, create/configure a Firebase project with Email/Password Authentication,
Cloud Firestore, and Cloud Functions, then follow
[FIREBASE_SETUP.md](FIREBASE_SETUP.md).

This repository contains the Android/macOS Firebase **client configuration**
required by the current project (`lib/firebase_options.dart`,
`android/app/google-services.json`, and
`macos/Runner/GoogleService-Info.plist`). Mobile Firebase API keys and app IDs
are identifiers for client apps, not server credentials. Before publishing or
releasing, restrict each key in Google Cloud to the correct Android package and
signing certificate or macOS bundle identifier, and to only the APIs it needs.

Never commit any of the following:

- Firebase service-account JSON or Firebase Admin credentials
- private keys, signing keystores, or signing-property files
- `.env` files, access tokens, or user data exports

Deploy the reviewed Firestore rules before enabling cloud sync:

```bash
firebase deploy --only firestore:rules
```

Deploy Functions after installing their dependencies:

```bash
cd functions
npm install
npm run deploy
```

The functions use Firebase's deployed runtime identity; no service-account JSON
belongs in this repository.

## Supabase

Supabase is not configured or used by the current application. Consequently,
there are no `SUPABASE_URL`, anon-key, service-role-key, or `--dart-define`
variables to provide. If Supabase is added later, supply client configuration
through local environment/`--dart-define` inputs and never commit a service-role
key.

## Security and privacy

- Local financial data stays in the on-device SQLite database unless the user
  enables Firebase sync.
- No UPI PIN, OTP, bank password, card number, or banking credential is stored.
- QR invitations contain an opaque ID and random token; Cloud Functions store
  only a token hash and create memberships transactionally.
- Firestore rules scope private operation logs to the authenticated user and
  prevent direct access to invitation hashes.

## Known limitations

- UPI payment completion is not externally verified.
- Partial settlements are not currently supported; a settlement records the
  exact suggested amount.
- Firebase sync is optional and requires the Firebase setup above.
