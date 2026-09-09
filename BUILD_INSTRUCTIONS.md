# How to Build & Compile the Android APK

## Prerequisites
- Flutter SDK installed ✓ (you already have it)
- Android SDK tools (should be installed with Flutter)
- Java JDK 11+ installed

## Step 1: Install Dependencies
Open PowerShell in the `C:\audiouploader` folder and run:
```
flutter pub get
```

## Step 2: Connect Your Wife's Phone (or use Emulator)
- Enable USB Debugging on her Android phone
- Connect via USB cable
- Verify connection:
```
flutter devices
```

## Step 3: Run the App (Test First)
```
flutter run
```
This will install and run the app on her phone for testing.

## Step 4: Build the Release APK
When ready to compile the final APK:
```
flutter build apk --release
```

The compiled APK will be at:
`C:\audiouploader\build\app\outputs\flutter-apk\app-release.apk`

## Step 5: Install on Wife's Phone
Either:
- **Option A:** Connect phone via USB and use:
  ```
  flutter install
  ```
- **Option B:** Copy the APK file and install manually:
  - Copy `app-release.apk` to the phone
  - Open file manager on phone
  - Tap the APK to install
  - Allow installation from unknown sources if prompted

## Step 6: First Run - Setup Google Sign-In
1. Wife opens the app
2. Taps "Sign in with Google"
3. Signs in with the Google account (turfscape.iafrica@gmail.com)
4. Grants permission to access Google Drive
5. Now she can select & upload MP3 files!

## Testing Workflow
1. Wife: Tap "Select & Upload MP3" → Choose an MP3 file
2. File uploads to "Audiobooks for Amanda" folder on Google Drive
3. Sister checks her tablet with the web app
4. New file appears automatically!

## Troubleshooting
- **"Module not found"**: Run `flutter pub get` again
- **"Android SDK not found"**: Run `flutter doctor` to see what's missing
- **Permission errors**: Make sure phone has storage permission granted

---

**Ready to test? Start with Step 1!**
