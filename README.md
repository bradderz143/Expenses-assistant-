# Expense Assistant

Scan receipts on your phone, group them by trip, and export one ZIP per trip.
Works on Android and iOS (built from the same code).

## The three tabs

1. **Scan**: pick the trip, photograph a receipt (or choose one from photos).
   The date and amount are read from the photo; check them and save. Anything
   the scan was not sure of is marked in red on the receipt, and the receipt
   shows **Check date** / **Check amount** in the lists until you have saved
   it. Tap **Translate to English** on a receipt only when you need a
   translated sheet.
2. **Trips**: create trips (name, country, start and end dates) and see their
   receipts. A trip can be set up afterwards: when you save it, the app
   offers the receipts from its dates that aren't in a trip yet, and
   **Add receipts to this trip** on the trip's page lets you pick any of
   them.
3. **Export**: one button per trip builds the ZIP and opens the share sheet
   (Save to Files / OneDrive, email, etc.).

## What comes out

```
Caracas_ACS_Workshop_2026-11-09.zip          trip name + trip start date
  2026-11-04_428.50MXN.jpg                   original photo: date, amount paid
  2026-11-04_428.50MXN_translated.pdf        only for receipts you translated
  2026-11-05_95.00MXN.jpg
```

Two receipts with the same date and amount get `_2`, `_3`… on the end.
Everything runs on the phone (ML Kit OCR, language ID and translation);
nothing is uploaded.

## Get it running

Requires a Flutter release that ships Dart 3.12 or later (check with
`flutter --version`; the ML Kit packages need it) and an Android device (Android 7.0 / API 24+) or an iPhone (iOS 15.5+).

```bash
cd expenses-assistant

# 1. Generate the platform folders. Existing files (lib/, test/, pubspec,
#    AndroidManifest.xml, proguard-rules.pro) are kept, not overwritten.
flutter create --org io.github.bradderz143 --project-name expense_assistant --platforms android,ios .

# 2. Dependencies
flutter pub get

# 3. Tests (pure Dart + SQLite via sqflite_common_ffi; needs libsqlite3 on
#    Linux: sudo apt install libsqlite3-dev)
flutter test

# 4. Run on a connected phone
flutter run
```

If the Android build complains about `minSdk`, set `minSdk = 24` in
`android/app/build.gradle.kts`. If `flutter pub get` reports a version
conflict between the three `google_mlkit_*` packages, align them to the
versions that share one `google_mlkit_commons` release.

Release build: `flutter build apk --release`. The bundled
`android/app/proguard-rules.pro` silences R8 warnings about ML Kit's optional
Chinese/Japanese/Korean/Devanagari OCR models.

> This code was written without a Flutter toolchain available, so it has not
> been compiled or run yet. Expect a few analyzer fixes on first
> `flutter analyze`; the SQL was checked against SQLite and the parsing
> regexes against sample receipts.

## The flow

1. **Scan**: the photo is straightened, trimmed to the receipt and saved as
   a draft immediately, so a receipt is never lost if you are interrupted.
   Date and amount are read on-device and pre-filled.

   The amount is not taken from one line on trust. A receipt states its total
   several ways (beside the word "total", as subtotal plus tax, as the sum of
   the item prices, as the amount paid, often in words: "TRES MIL SETECIENTOS
   SESENTA PESOS 00/100") and the scan wants two of them to agree. A count
   such as "Total de productos: 24" is never the amount. When nothing backs
   the figure it found, or no total could be read and it had to add up the
   items, the amount is marked **Hard to read. Please check**.

   The date works the same way: a date it could not read falls back to the
   day of the scan and says so; a date found only inside a ticket number, or
   one of several different dates, is marked for a check.
2. **Translate (optional)**: only when you ask. Drag a crop round the items
   (or the whole text for non-meal receipts); each line is translated from the
   glossary first, then by the on-device model. You review and save, and a
   translated sheet (PDF) is generated for that receipt.
3. **Export**: pick a trip, get the ZIP, send it to Files/OneDrive or email.

## iOS

The iOS build runs on a GitHub Actions Mac runner (commit message containing
`[ios]`, or Run workflow with "iOS" ticked) and produces an **unsigned IPA**.
It must be signed with an Apple certificate before it installs, so give it to
your IT team to sign and deploy through your device management.

## Code layout

```
lib/
  domain/            pure Dart, no Flutter
    entities/        Receipt, Trip, TranslationLine, ExpensePackage, settings
    value_objects/   Money (integer minor units)
    reference/       Oracle claim categories, countries, currencies
    logic/           OCR row assembly, receipt parser, item-line parser,
                     package naming, claim summary/metadata builders
    repositories/    repository interfaces
    services/        OCR / translation / PDF interfaces
  data/
    db/              SQLite schema + migrations, row mappers
    repositories/    sqflite implementations
    services/        ML Kit OCR + translation, PDF renderer, file storage
  application/       use cases: capture, translate, package rebuild,
                     receipt/trip commands, export
  presentation/      Riverpod providers and screens
test/                parser, naming, documents, full workflow, widgets
```

Clean-architecture rule: `domain` imports nothing outside itself;
`application` depends on domain interfaces; `data` implements them;
`presentation` wires them together in `providers.dart`.

## Extension points (not built)

| Future feature | Where it plugs in |
| --- | --- |
| OneDrive sync | new `SyncService` called after `PackageService.rebuild` |
| Outlook email | `ExportService` result -> Graph API instead of share sheet |
| Card statement matching | new `transactions` table + matcher on `amount_minor`, date, merchant |
| AI categorisation / justification / meal detection | implement against `ReceiptTextParser` output; keep the user confirm step |
| Currency conversion | `Money` + a rates repository |
| Cloud translation | another `TranslationService` implementation |
