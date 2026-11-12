# DollyDesk Door

Flutter Android/iOS app for cowork members, derived from [project-not-here-mobile](https://github.com/azriel68/project-not-here-mobile). It does one thing: open and close the doors the member can access.

- Login: choose a cowork from the searchable list, then sign in. The login always asks for the long-life token (`stayConnected: true`, as on the website), stored in secure device storage; on every launch the token is validated with `GET /me` and the user goes straight to the doors.
- Doors: a single screen. With one door, two large buttons (Ouvrir / Fermer); with several, one card per door with its two buttons. The list (`GET /the-place-to-work` smartlocks, limited to shared doors and the rooms of today's reservations) and the rights (`GET /user/door/access`) refresh on pull-down and when the app returns to the foreground. Commands go to `POST /user/door/{id}/open|close` with the device position.
- When the API refuses the token (401), the app returns to login with the cowork and email remembered.

## API setup

The versioned `.env` sets the production API URL to `https://api.relaiscoworking.fr/`. For local development, copy `.env.local.example` to `.env.local`; its value overrides `.env`:

```powershell
Copy-Item .env.local.example .env.local
```

The local file is git-ignored. Both files are bundled with the app, so put only public configuration such as the API base URL in them, never credentials or keys. The API destination is fixed for each app build and cannot be changed from the login screen. Build-time URL priority is `--dart-define=API_BASE_URL=...`, then `.env.local`, then `.env`.

The configured API server must expose `GET /mobile/places`. The Symfony API in this repository provides the route and limits its response to enabled coworks' public selection fields; deploy this API change to the configured server before using the mobile app. The selected cowork ID is sent in the `Coworkid` header.

The selected cowork and email are remembered between launches. The app stores the API's long-life access token in secure device storage and validates it on startup, restoring the session automatically while it is still valid. When it expires, the app returns to login with the cowork and email remembered.

At startup, when the configured URL differs from the production URL in `.env`, the app checks that the server answers (3 s timeout). If it does not, the app falls back to the production API. Switching API forgets the selected cowork and the session, but keeps the email. While in development (debug and profile builds), a pill at the top of the screen shows `TEST` or `PRODUCTION` for the API in use. It does not appear in release builds.

The development URL in `.env.local.example` is `http://127.0.0.1:8000/`. On a USB-connected Android phone, forward the local API port before launching the app:

```powershell
adb reverse tcp:8000 tcp:8000
```

On an Android emulator, set `.env.local` to `http://10.0.2.2:8000/` instead. On a phone connected over Wi-Fi, configure the development server to listen on the computer's network interface and use its LAN IP in `.env.local`.

## Checks and builds

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

Android builds use compile SDK 34 and Kotlin Gradle plugin 1.9.0 to satisfy the location plugin requirements. Android application ID / iOS bundle ID: `com.dollydesk.door`. `.env.local` must exist to build (copy it from `.env.local.example`). iOS builds require macOS and Xcode.

## Production APK

Release builds are signed with the key described in `android/key.properties` (git-ignored, with the `.jks` it points to). Without that file, they fall back to the debug key. Keep the keystore and its passwords: every update must be signed with the same key.

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.relaiscoworking.fr/
```

The `--dart-define` pins the production API whatever `.env.local` says.
