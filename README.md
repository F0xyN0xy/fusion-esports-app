# Fusion Esports

> Community app for Fusion Esports team members.

[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey?logo=android&logoColor=white)](../../releases)
[![Release](https://img.shields.io/github/v/release/f0xyn0xy/fusion-esports-app?label=latest&color=blueviolet)](../../releases/latest)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Download

| Platform | Instructions |
|----------|-------------|
| 🤖 **Android** | [Download latest APK](../../releases/latest) — see install guide below |
| 🍎 **iOS** | Requires TestFlight invite — contact a team admin |

### Android Install Guide
1. Go to [**Releases**](../../releases) and download the latest `.apk`
2. On your phone, go to **Settings → Security** and enable **Install from unknown sources**
3. Open the downloaded APK and tap **Install**
4. Launch **Fusion Esports** from your home screen

> **Requires Android 6.0 or higher**

---

## Features

- **Discord OAuth** — sign in with your Discord account
- **Tournament Schedule** — upcoming matches with live countdowns
- **XP Leaderboard** — stats and rankings across all team members
- **Role Management** — view and manage team roles
- **Push Notifications** — stay updated on matches and announcements
- **Announcements** — team news and updates in one place

---

## Build from Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.0
- Android Studio or VS Code with Flutter & Dart extensions
- Android device or emulator (Android 6.0+)
- For iOS: macOS with Xcode 14+

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/f0xyn0xy/fusion-esports-app.git
cd fusion-esports-app

# 2. Install dependencies
flutter pub get

# 3. Run in development
flutter run

# 4. Build release APK (Android)
flutter build apk --release

# 5. Build release IPA (iOS — macOS only)
flutter build ipa --release
```

The Android APK will be at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## Contributing

This is a private team app. If you're a Fusion Esports member and want to contribute, reach out to a team admin for access.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.