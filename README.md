# 📸 Passport Photo Printer

A **Flutter** app for printing professional passport-size photos and ID card sheets — designed for print shops and hotel photo services.

> Built with Flutter · Works on **Android** and **Web**

---

## ✨ Features

- **AutoPassport** — Upload a portrait, remove background, choose a background colour, and generate a perfect 48-photo A4 PDF sheet (6×8 grid) ready to print
- **ID Maker** — Scan or upload an Aadhaar/PAN/any ID card, auto-crop to card ratio, apply filters, and export a dual-sided A4 ID sheet PDF
- **AI Background Removal** — Uses the [remove.bg](https://remove.bg) API to cleanly cut out the person from any background
- **Remini HD Filter** — 8-neighbour sharpening convolution for crisp, high-definition faces before printing
- **PDF Enhancer** — Choose Original / Magic Color / Remini HD / B&W before generating your print sheet

---

## 🚀 Getting Started

### 1. Prerequisites

- Flutter SDK `>=3.10.0`
- Android Studio / VS Code with Flutter plugin
- A free [remove.bg](https://www.remove.bg/api) API key

### 2. Clone the repo

```bash
git clone https://github.com/psmish77/passport-photo-printer.git
cd passport-photo-printer
flutter pub get
```

### 3. Add your remove.bg API key

The app reads the API key from **`SharedPreferences`** — stored via the Settings screen.

**Option A — Enter it manually in the app:**
1. Open the app → tap **Settings** (bottom nav)
2. Tap the **🔄 Sync** icon
3. The key is loaded from your configured Vercel endpoint (see Option B)

**Option B — Auto-sync via a Vercel config file (recommended):**

1. Create a file at `public/config.json` in your own Vercel-deployed project:

```json
{
  "remove_bg_api_key": "YOUR_REMOVE_BG_API_KEY_HERE",
  "app_version": "1.0.0"
}
```

2. Open **`lib/main.dart`** and update the URL in `_autoSyncApiKey()`:

```dart
// Around line 35 in main.dart — replace with YOUR Vercel deployment URL:
final response = await http.get(
  Uri.parse('https://YOUR-PROJECT.vercel.app/config.json'),
);
```

3. Push to GitHub → Vercel auto-deploys. The app will pick up the new key on next launch.

**Get a free remove.bg API key:**
👉 [https://www.remove.bg/api](https://www.remove.bg/api) — free tier includes 50 API calls/month

---

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point, auto-sync API key
├── screens/
│   ├── passport_tool.dart       # AutoPassport screen
│   ├── id_card_tool.dart        # ID Maker screen
│   └── settings_screen.dart     # Settings & API key status
└── services/
    ├── document_enhancement_service.dart  # Remini HD / Magic / B&W filters
    ├── document_scanner_service.dart      # Native document scanner
    ├── ocr_service.dart                   # ML Kit OCR
    └── qrcode_service.dart                # ML Kit Barcode scanner
```

---

## 🔑 Where to find/set the API key

| Location | Purpose |
|---|---|
| `lib/main.dart` → `_autoSyncApiKey()` | URL to fetch key from (change to your Vercel URL) |
| `lib/screens/settings_screen.dart` → `_syncFromCloud()` | Same URL used when user taps Sync |
| `SharedPreferences` key: `REMOVE_BG_API_KEY` | Where the key is stored at runtime |

---

## 🏗️ Cross-Platform Architecture & Resource Optimization

### 1. Cross-Platform Compilation (Web & Mobile Coexistence)
Flutter Web and native Mobile targets have different API availabilities. To build the application for both targets simultaneously:
- **`dart:io` & `dart:js` Mitigation**: Native platforms support file-system access (`dart:io`), while Web supports browser interop (`dart:js`, `dart:html`). Direct imports of these on the wrong platform cause fatal compile-time errors.
- **Conditional Imports & Stubs**:
  - We implemented a web-safe stub (`web_io_stub.dart`) to mock `File` and `Platform` on Web.
  - We implemented custom browser stubs (`web_utils.dart` and `web_utils_web.dart`) to mock URL-opening behavior (`dart:html` wrapper) conditionally:
    ```dart
    import 'web_utils.dart' if (dart.library.html) 'web_utils_web.dart' as web_utils;
    ```
- **Dummy Environment Asset**: The project uses a `.env` file for API key configurations. Since `.env` is ignored by Git, clean build environments (Vercel and GitHub Actions CI) would crash trying to resolve it as a declared asset. We resolved this by adding automatic dummy `.env` generation to the build scripts.

### 2. Resource Optimization
This app is designed to run with a minimal hardware footprint:
- **Play Services Scanner Offloading**: Instead of compiling massive C++ OpenCV binaries or running custom edge detection scripts in Dart, we offload document scanning, border-cropping, and perspective warping to the native **Google Play Services Document Scanner API**.
- **GPU Preview Acceleration**: Brightness, contrast, and saturation previews are processed at 60/120 FPS directly on the GPU using color matrix shaders, completely skipping CPU pixel-level iteration.
- **Isolate Offloading**: Heavy tasks (like the Remini HD 3x3 sharpening convolution kernel and local background segmentations) are offloaded to Dart isolates (`compute` thread pools), keeping the UI thread completely smooth.
- **Downscale-on-Load**: Images are resized immediately upon picking (max width 450px for passport photo grid cells), dropping memory consumption by over 90% during PDF compilation.

---

## 📦 Building

```bash
# Web
flutter build web --release

# Android APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🛠 Tech Stack

- **Flutter** (Dart)
- **remove.bg API** — AI background removal
- **Google ML Kit** — OCR & Barcode scanning (Android)
- **pdf / printing** — PDF generation and printing
- **image** — Dart image processing (convolution, filters)

---

## 📄 License

MIT License — free to use, modify and distribute.
