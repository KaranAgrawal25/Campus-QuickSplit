# Firebase setup

Campus QuickSplit is local-first. SQLite remains the source of truth; without
Firebase configuration, every expense, balance, settlement, backup, and export
continues to work offline.

Firebase is optional and is used only for an authenticated account's durable
sync outbox. Do not add API keys, service-account JSON, or production project
files to this repository.

1. Create a Firebase project and enable **Email/Password** authentication,
   **Cloud Firestore**, and **Cloud Functions**.
2. Install the Firebase CLI and FlutterFire CLI, then run the following from
   the project root:

   ```bash
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

   Select Android and macOS as applicable. The command creates the local
   `lib/firebase_options.dart` and platform configuration files. Firebase app
   identifiers are not secrets; never add a service-account credential file.
3. Install Functions dependencies and deploy the trusted invitation backend:

   ```bash
   cd functions && npm install && npm run deploy
   ```

4. Deploy [`firestore.rules`](firestore.rules) before enabling sync for users.
   The file limits access to the authenticated account's own private operation
   log. With the Firebase CLI, use `firebase init firestore` and deploy the
   copied rules using `firebase deploy --only firestore:rules`.
5. The sync outbox is private to the authenticated account. Group invitation
   creation and joining are authorized by Cloud Functions, which store only a
   SHA-256 invite-token hash and create memberships transactionally.

The app never uploads receipt image files, UPI credentials, passwords, or device-lock
credentials. Firebase project identifiers are not secrets, but service account
credentials always are and must never be bundled into the app.
