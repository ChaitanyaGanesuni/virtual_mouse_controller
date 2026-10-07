# Releasing the app

How to produce an APK signed with **your** key. You do this once; after
that, every CI build is signed the same way.

## Why your own key matters

Android only installs an update over an existing app if both are signed with
the same key. Until you add yours, CI signs with a **throwaway test key**
that changes on every run. Those APKs are fine for testing, but each new one
must be installed fresh, and uninstalling deletes the data on the phone (sync
it first).

**Keep the key safe.** If it is lost, existing installations can never be
updated again; people would have to uninstall and reinstall. Keep two
backups (for example, a password manager and an offline copy), and never put
it in the repository. `android/.gitignore` already ignores `key.properties`,
`*.jks` and `*.keystore`.

## 1. Create the key (once)

You need Java's `keytool`, which comes with any JDK or with Android Studio:

```bash
keytool -genkeypair -v -keystore gita-release.jks -alias gita \
  -keyalg RSA -keysize 4096 -validity 10000
```

It asks for a password and your name. Use a long random password and keep
it with the key.

## 2. Let CI sign with it

Go to GitHub → the repository → **Settings → Secrets and variables →
Actions → New repository secret**, and add four secrets:

| Secret | Value |
|---|---|
| `GITA_KEYSTORE_BASE64` | the key file as text: `base64 -w0 gita-release.jks` (macOS: `base64 -i gita-release.jks`) |
| `GITA_KEYSTORE_PASSWORD` | the keystore password |
| `GITA_KEY_ALIAS` | `gita` (the `-alias` above) |
| `GITA_KEY_PASSWORD` | the key password (the same as the keystore password unless you chose another) |

The next CI run builds:

- `app-release.apk`, which works on any phone;
- `app-arm64-v8a-release.apk` and `app-armeabi-v7a-release.apk`, which are smaller and made for each phone type.

The job log says **"Signed with: release key"** and prints the certificate's
SHA-256, so you can check it is yours. The artifact *gita-companion-debug-symbols* is needed to read crash
reports. Dart code is obfuscated, so keep the symbols for each release.

## 3. Or sign on your own computer

Create `gita-companion/mobile/android/key.properties` (it is git-ignored):

```properties
storeFile=/absolute/path/to/gita-release.jks
storePassword=...
keyAlias=gita
keyPassword=...
```

Then build:

```bash
cd gita-companion/mobile
tool/sync_content.sh
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_BASE_URL=https://your-server.onrender.com
```

## 4. Before publishing

Go through [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md). For the Play
Store, also build an App Bundle (`flutter build appbundle` with the same
flags). Play then needs this key as the *upload key*, and Play App Signing
keeps the final signing key.
