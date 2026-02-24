# book_reader

A simple cross-device book reader (Mac & Android) with synced reading position, notes, and highlights. Uses Firebase Firestore and Storage (no auth).

## Firebase setup

1. Create a [Firebase project](https://console.firebase.google.com) and enable **Cloud Firestore** and **Storage**.
2. Set Firestore and Storage rules to allow read/write (e.g. `allow read, write: if true;`) if you use no auth.
3. Run: `dart pub global activate flutterfire_cli` then `flutterfire configure`. Select your project and platforms (Android, macOS). This generates `lib/firebase_options.dart` and adds `google-services.json` for Android.
4. Replace the placeholder `lib/firebase_options.dart` with the generated file.

## Running

- macOS: `flutter run -d macos`
- Android: `flutter run -d android`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
