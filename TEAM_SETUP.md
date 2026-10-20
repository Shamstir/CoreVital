# SubZero team setup

This guide gets a teammate running the existing shared Firebase project and
already-deployed Cloudflare Worker. It does **not** require a Cloudflare login
or a Worker deployment.

## Send these privately

1. Access to both repositories:
   - `https://github.com/Shamstir/CoreVital.git`
   - `https://github.com/Shamstir/subzero.git`
2. The macOS Firebase configuration file:
   - `GoogleService-Info.plist`
3. The Android Firebase configuration file:
   - `google-services.json`
4. The Worker URL:

   ```text
   https://subzero-fcm.bahubali1267354.workers.dev
   ```

5. The Firebase account credentials they should use in the Android app, or an
   invitation to the shared Firebase project.

They do **not** need the Cloudflare account, API token, KV namespace ID, or
Firebase service-account JSON just to run the apps and use the deployed Worker.
Those are needed only by someone who must change or redeploy the Worker.

## One-time Firebase setup

In Firebase Console, make sure the same project has these enabled:

- Firestore Database
- Authentication → Email/Password
- Cloud Messaging

For this private demo, publish these Firestore rules. They allow the Mac to
write telemetry without macOS Firebase Auth / Keychain access:

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /devices/{deviceId} {
      allow read, write: if true;
    }
  }
}
```

## macOS app

### Prerequisites

- macOS 13 or newer
- Xcode
- An Apple ID signed in to Xcode (a Personal Team is enough for local running)

### Setup

```bash
git clone https://github.com/Shamstir/CoreVital.git
cd CoreVital
```

Copy the privately shared Firebase file to:

```text
CoreVital/SubZero/GoogleService-Info.plist
```

Open `CoreVital/SubZero.xcodeproj` in Xcode. Select the **SubZero** target,
choose their Personal Team under **Signing & Capabilities**, then press **⌘R**.

The Worker URL is already committed in `SubZero/Info.plist`. Do not change it
unless the Worker is redeployed to another URL.

## Android app

### Prerequisites

- Flutter SDK
- Android Studio / Android SDK
- A physical Android phone with USB debugging, or an emulator with Google Play
  services

### Setup

```bash
git clone https://github.com/Shamstir/subzero.git
cd subzero
flutter pub get
```

Copy the privately shared Firebase file to:

```text
subzero/android/app/google-services.json
```

Run the app with the deployed Worker URL:

```bash
flutter run --dart-define=SUBZERO_PAIRING_WORKER_URL=https://subzero-fcm.bahubali1267354.workers.dev
```

For a release APK, keep the same `--dart-define`:

```bash
flutter build apk --release --dart-define=SUBZERO_PAIRING_WORKER_URL=https://subzero-fcm.bahubali1267354.workers.dev
```

## Test checklist

1. Open the macOS app and wait a few seconds.
2. Sign in to the Android app with an Email/Password Firebase account.
3. Open the Android dashboard. Mac telemetry should appear through Firestore.
4. On the Mac, open Preferences and generate a pairing code.
5. On Android, open Settings → **Pair a Mac for Push Alerts**, then enter the
   12-character code.
6. On the Mac, click **Trigger Test Alert to Android Phone**. Lock or close the
   Android app to confirm that it arrives as an FCM notification.

## External ESP fan command

The Android dashboard includes **Start Fan** and **Stop Fan** under
**External ESP Cooling Fan**. These write an `externalFanOn` or
`externalFanOff` command to the Mac's Firestore device document.

The macOS app receives the command and stores the current state as
`externalFanCommand` (`on` / `off`). The final bridge from macOS to the
separate ESP fan is intentionally not implemented yet because it depends on
the ESP connection method and protocol (USB serial, Wi-Fi HTTP, Bluetooth,
etc.).

## If someone needs to redeploy the Worker

Only a maintainer should do this. They need Cloudflare access to the existing
account plus the Firebase project ID and service-account JSON stored as Worker
secrets. From `CoreVital/SubZero/cloudflare-worker`:

```bash
npm install
npx wrangler login
npx wrangler deploy
```

The Worker source is in `cloudflare-worker/src/index.js` and its deployment
configuration is in `cloudflare-worker/wrangler.toml`.
