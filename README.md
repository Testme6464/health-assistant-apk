# Health Assistant APK — ကျန်းမာရေး

Flutter APK for the Health Assistant app (Burmese UI). Stage 1 skeleton:
Google sign-in (Firebase Auth), 12-tab shell, VideoTool-style API Keys tab,
offline-first Firestore sync. The full feature port of the web app is stage 2.

- **Firebase project:** Health Assistant (`health-assistant-65709`, Spark plan — free)
- **Package:** `com.tryo.healthassistant`
- **Web app (live):** https://health-assistant-kappa-mocha.vercel.app/
- **Plan:** `~/workspace/goals/health-assistant-app/apk-plan.md`

## Build (GitHub Actions)

Every push to `main` builds a debug APK and publishes it as a GitHub
Release (`v0.1.0`). No PC needed — the build runs in CI, exactly like
VideoTool. Download the APK from the repo's Releases page.

## Local build

```sh
flutter pub get
flutter analyze
flutter build apk --debug
```

Requires Flutter 3.47.x stable + Java 17. `google-services.json` is already
in `android/app/` (Firebase client config — standard for FlutterFire).

## Still to do

1. **Create the GitHub repo** `Testme6464/health-assistant-apk` and push this
   code (see below).
2. **Deploy Firestore rules** (`firestore.rules`) in Firebase console
   (Firestore > Rules) — production-mode rules currently deny everything.
3. **SHA-1 fingerprint:** after the first release-keystore decision, add the
   signing keystore's SHA-1 in Firebase console (Project settings > Android
   app) so Google sign-in works in release builds. Debug builds work without it.
4. **Stage 2 — full tab port:** Home (real summary), Food (60-food DB +
   photo AI), Progress charts, Meds (30 drug interactions), Plan (BMI →
   goal → meals/workout), Period, Symptom, Reminders, Profile, Report (PDF),
   Emergency. Data models + static data are already in `lib/`.
5. **Stage 3 — Health Connect** (steps / exercise / calories auto-sync).

## Data model

Mirrors the web app's localStorage schema (`healthAppV1`), so the web JSON
export can be imported. Firestore layout:

```
users/{uid}/{collection}/{docId}   — profiles, meds, foodLog, sleepLog,
                                     activityLog, weightLog, symptoms,
                                     emergencyContacts, periodLog, mealPlans
users/{uid}/meta/{collection}      — settings, reminders, plans, waterLog
```

Local cache (SharedPreferences JSON) is the source of truth for the UI;
`SyncService` pushes dirty collections and pulls changes newer than the last
sync whenever the phone is online.
