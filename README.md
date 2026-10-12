# SwiftReceipt

Offline-first receipt capture and reconciliation for restaurants, cafes, hotels and retail.
Flutter (Material 3) + on-device ML Kit OCR + SQLite outbox + Supabase (Postgres, Auth, Realtime, Storage).

## What's inside

| Area | Features |
|---|---|
| Waiter | Instant camera launch, framed viewfinder, torch, haptics, on-device OCR (amount / reference / provider / sender / time), editable review sheet, local duplicate check, image compression (<100 KB), running shift total, day-by-day ledger with status pills, 100% offline |
| Sync | Outbox worker (connectivity trigger + 45 s timer + pull-to-refresh), idempotent upserts (`org_id, local_id`), image upload to private bucket, cloud duplicate flagging returned to the device |
| Manager | Realtime live feed, per-staff filter, flagged-only filter, signed receipt photos, "mark reviewed", insights (revenue per staff, provider donut, hourly peaks, 1/7/30 days), end-of-day audit (transfers + cash vs billed), team screen with join code and role management |
| Notifications | Local notifications **with sound**: sync results, duplicate alerts, and manager "new payment" alerts driven by Realtime. Separate Android channels for sound on/off; test button in Settings |
| Theme | Light / dark / auto, 5 accent colours, persisted |
| Security | Row Level Security everywhere, private storage bucket scoped by organization, roles (waiter, cashier, manager, owner) |
| Retention | `pg_cron` nightly purge (cloud) + startup cleanup (device) of images older than 7 days; text records kept forever |

## 1. Supabase setup

1. Create a project at supabase.com.
2. **Database → Extensions**: enable `pg_cron`.
3. **SQL editor**: paste and run `supabase/schema.sql`.
4. **Authentication → Providers → Email**: turn **off** "Confirm email" (staff sign in with email + PIN/password right away).
5. Copy the project URL and anon key (**Project Settings → API**).

## 2. Flutter setup (Flutter 3.27+)

This archive contains the Dart code and config only. Generate the native folders once:

```bash
cd swiftreceipt
flutter create . --org com.swiftreceipt --project-name swiftreceipt
flutter pub get
```

If `flutter create` generated `test/widget_test.dart`, delete it (it references a template widget); `test/ocr_parser_test.dart` is the real test.

### Android (`android/app/build.gradle(.kts)` and manifest)

- `minSdk = 24`
- Enable desugaring (required by flutter_local_notifications):
  ```
  compileOptions { isCoreLibraryDesugaringEnabled = true }   // Kotlin DSL
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
  ```
- `AndroidManifest.xml`, inside `<manifest>`:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  <uses-permission android:name="android.permission.VIBRATE"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  ```

### iOS

- `ios/Podfile`: `platform :ios, '15.5'`
- `ios/Runner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>SwiftReceipt scans payment confirmations with the camera.</string>
  ```

## 3. Run

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

Release builds: add the same `--dart-define` flags to `flutter build apk` / `flutter build ipa`.

## 4. First-run flow

1. Open the app → **New business** → creates your organization and makes you the **owner** (manager dashboard).
2. Settings (or the Team screen) shows the **join code**. Give it to staff.
3. Staff choose **Join team**, enter the code, and land on the camera screen as waiters.
4. Owner can promote staff to cashier / manager in **Team**.

## Notes and deliberate deviations from the blueprint

- **Auth:** Supabase Auth (email + password/PIN) with a `profiles` table, instead of a custom `users.pin_code_hash`. Safer, and works with RLS.
- **Duplicates:** the blueprint's unique index on `(org_id, reference_number)` would reject duplicates, which contradicts "flag duplicates". The index is non-unique; a trigger sets `is_flagged` on both rows. Managers can mark a flag as reviewed.
- **Local DB:** `sqflite` (no code generation) instead of `drift`, so the project builds without `build_runner`. Riverpod providers are hand-written for the same reason.
- **Sync:** rows upload one at a time so each image path and its row stay together; a network error pauses the queue, a server-side rejection marks the row `failed`.
- **Notifications:** these are local notifications. They fire while the app is open or alive in the background (Realtime connection). For alerts when the app is fully closed you need push (Firebase Cloud Messaging + an Edge Function triggered by inserts on `transactions`); that is not included.
- **Custom sound:** to use your own tone, add a file to `android/app/src/main/res/raw/` and set `sound: RawResourceAndroidNotificationSound('name')` in `notification_service.dart` (use a new channel id, since Android channels are immutable).
- **Fonts:** `google_fonts` downloads fonts on first use. For fully offline first launch, bundle the font files and register them in `pubspec.yaml`.
- **Storage purge:** the nightly job deletes `storage.objects` rows directly. If you want a guaranteed removal of the underlying files, replace it with an Edge Function that calls the Storage API.
- **OCR accuracy:** the parser is tuned for Telebirr, CBE and similar layouts. The review sheet exists because OCR can misread; extend `lib/services/ocr_parser.dart` for your providers.
- This project was written without a Flutter toolchain available, so it has not been compiled. Run `flutter pub get && flutter analyze`; if a package version drifts, `flutter pub upgrade` plus small API tweaks should resolve it.
