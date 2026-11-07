# RetroPlay – Classic Gaming Hub

A personal Android game library and launcher, built for a Google Pixel 9 (Tensor G4, Mali-G715 MC7)
running Android 15 or later.

RetroPlay **does not bundle, download or distribute any game**, game asset, executable or emulator.
It only organises and launches software the user already owns and has installed.

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Project foundation (Kotlin, Compose, MVVM, Hilt, Room, DataStore, Navigation, Coil) | ✅ Done |
| 2 | `DeviceProfileManager` + Settings › Device information + Pixel 9 reference comparison | ✅ Done |
| 3 | Full launcher UI (home, library, discover, favourites, game detail, compatibility report) | ✅ Done |
| 4 | Initial game catalogue (9 entries, metadata only) | ✅ Done |
| 5 | `GameLaunchManager` (Android games, external emulator, unsupported handler) | ✅ Done |
| 6 | Storage Access Framework import | Not started |
| 7 | Mali / Tensor G4 compatibility profile + `CompatibilityManager` | Not started |
| 8 | Room entities, DAOs, repositories | Partial: `GameEntity`, `FavoriteEntity`, `PlayHistoryEntity` (schema v2 with migration) |
| 9 | Full test suite | Partial (tests for Phases 1–5) |

## What works in this build

- **Home**: hero banner, *Continue playing*, favourites, a library carousel and a device shortcut.
- **Library**: search plus category filters over an adaptive grid of game cards.
- **Discover**: browsable collections (GTA, Cricket, 2000s PC classics, games awaiting a test).
- **Favourites**: games you've marked with the heart, saved in Room.
- **Game detail**: artwork, metadata, execution type, installation and compatibility status, last played,
  and personal notes you can edit (saved in Room), plus a **Launch** card that shows only actions RetroPlay can really perform (see below).
- **Compatibility report** (Settings): the test device summary, status counts, each game's status, and a status legend.
- **Settings**: device information, compatibility report, your **Windows compatibility app**, the *Pixel 9 reference comparison* toggle (saved in DataStore), and app version.

### Launching (Phase 5)

`GameLaunchManager` picks a launch plan per game. Every button shown corresponds to something RetroPlay really does:

| Situation | What RetroPlay does |
|---|---|
| Android game installed | **Play** opens the app via its standard launcher intent, then records play history and *last played*. |
| Android game not installed | Explains why. **Store listing** opens the store page so you can install it yourself, and **Link installed app** lets you pick another edition you own. Nothing is installed automatically. |
| Windows game, compatibility app chosen | **Open <app>** opens your chosen app (for example Winlator) via its launcher intent, followed by numbered manual steps. This is logged as "opened" and never counts as played. |
| Windows game, no app chosen / app uninstalled | Shows the manual steps and a **Choose compatibility app** button. |
| Unsupported (by configuration or by a recorded test) | `UnsupportedGameHandler` shows the reasons, the required environment, and whether a test was actually run. |

What it deliberately does **not** do:
- Assume a Winlator package name, intent action, deep link or API. You choose the app; apps whose label contains "Winlator" are only *suggested* in the picker.
- Pass game files or paths to the other app, or change its configuration.
- Request `QUERY_ALL_PACKAGES`. Visibility comes from `<queries>` for launcher apps, the store, and the three catalogue packages.

The Android editions are pre-linked to the Rockstar Games packages `com.rockstargames.gta3`, `com.rockstargames.gtavc` and
`com.rockstargames.gtasa`. Installation is always checked on the device, and you can link a different installed edition.

### Game catalogue

Metadata only. No game files, assets or executables are included. Artwork is generated in-app
(a gradient, the category icon and a monogram) until you supply licensed images.

| Game | Category | Edition | Year | Compatibility |
|---|---|---|---|---|
| EA Sports Cricket 07 | Cricket | Windows PC | 2006 | Not tested |
| Grand Theft Auto III | GTA | Windows PC | 2002 | Not tested |
| Grand Theft Auto: Vice City | GTA | Windows PC | 2003 | Not tested |
| Grand Theft Auto: San Andreas | GTA | Windows PC | 2005 | Not tested |
| Grand Theft Auto IV | GTA | Windows PC | 2008 | Not tested |
| Grand Theft Auto V | GTA | Windows PC | 2015 | Not tested |
| Grand Theft Auto III (Android) | GTA | Android | 2011 | Not tested |
| Grand Theft Auto: Vice City (Android) | GTA | Android | 2012 | Not tested |
| Grand Theft Auto: San Andreas (Android) | GTA | Android | 2013 | Not tested |

The catalogue is seeded with insert-if-absent, so your notes and favourites are never overwritten.

- **Settings › Device information**: a hardware profile measured **at runtime** on the phone:
  - Android version, API level, security patch and build
  - CPU ABIs, 64-bit support, core count, and per-cluster max clocks (when sysfs is readable)
  - Total (OS-visible), available and low-memory threshold RAM, plus app heap classes
  - GPU renderer, vendor, GL ES driver, GLSL and EGL versions (from a temporary 1×1 off-screen EGL context)
  - Graphics APIs: OpenGL ES version, Android Extension Pack, highest Vulkan version, Vulkan hardware level
  - Physical resolution, density, current/max/supported refresh rates, HDR
  - Internal storage available/total, and current thermal status
  - A comparison against the **Pixel 9 reference profile** (spec-sheet values, clearly labelled as
    reference rather than measurement) with a *Matches / Differs / Unavailable* verdict per field.

No Pixel 9 value is hard-coded as a measurement. If the platform does not expose a value, the UI says
“Not reported” or “Not obtainable” rather than guessing.

## Architecture

Single Gradle module (`app`) with layered packages under `com.retroplay.app`:

```
core/           theme (dark, purple/electric-blue), shared Compose components, formatters, dispatcher qualifiers
domain/         pure Kotlin: models, Pixel 9 reference profile, DeviceProfileComparator, repository interfaces
compatibility/  DeviceProfileManager + DeviceInfoSource / GpuInfoProvider contracts
data/           Android implementations (AndroidDeviceInfoSource, EglGpuInfoProvider)
settings/       DataStore-backed UserPreferencesRepository
presentation/   Compose screens + Hilt ViewModels (home, settings, deviceinfo)
navigation/     type-safe Navigation Compose routes, NavHost, bottom-bar shell
launcher/       (Phase 5)    storage/  (Phase 6)
data/local/     Room database, entities and DAOs (schema exported to app/schemas/)
di/             Hilt modules
```

Data flows one way: platform APIs → `DeviceInfoSource` → `DeviceProfileManager` → `DeviceInfoViewModel`
(a `StateFlow` combined with DataStore preferences) → Compose UI.

### Tech stack

AGP 8.7.3 · Gradle 8.14.3 · Kotlin 2.0.21 · KSP · Compose BOM 2024.12.01 · Material 3 · Hilt 2.52 ·
Navigation Compose 2.8.5 · Room 2.6.1 · DataStore 1.1.1 · Coil 2.7 · Coroutines 1.9 ·
JUnit 4 · Robolectric 4.14 · Compose UI Test.

`compileSdk`, `targetSdk` and `minSdk` are all **35** (Android 15). The app also runs on later versions.

## Building

Requirements: JDK 17 or newer (Android Studio’s bundled JBR works), and Android SDK Platform 35 with
Build-Tools 35. Android Studio Ladybug or newer opens the `RetroPlay/` folder directly.

From the command line, point Gradle at your SDK by creating `RetroPlay/local.properties`:

```
sdk.dir=C\:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
```

or by setting the `ANDROID_HOME` environment variable. Then:

**Windows**
```
cd RetroPlay
.\gradlew.bat assembleDebug
.\gradlew.bat testDebugUnitTest
```

**macOS / Linux**
```
cd RetroPlay
./gradlew assembleDebug
./gradlew testDebugUnitTest
```

The debug APK is written to `app/build/outputs/apk/debug/app-debug.apk`. To install it on a connected Pixel
with USB debugging enabled:

```
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Tests (Phases 1–5)

All tests run on the JVM (`testDebugUnitTest`); no emulator is needed:

- `DeviceProfileComparatorTest`: verdict rules, RAM tolerance limits, landscape resolution, API level.
- `DefaultDeviceProfileManagerTest`: profile assembly, GPU caching, GPU failure handling.
- `AndroidDeviceInfoSourceTest` (Robolectric, API 35): the real platform-reading code against simulated framework services.
- `DeviceInfoViewModelTest` / `SettingsViewModelTest`: UI state, error/retry, and preference toggling.
- `DataStoreUserPreferencesRepositoryTest`: defaults and persistence.
- `DeviceInfoSectionsTest`: display mapping and the “not reported” labels.
- `DeviceInfoContentTest` (Compose UI on Robolectric): rendering, comparison toggle, retry/back actions.
- `GameCatalogueTest` / `GameFilterTest`: catalogue contents, unique IDs, NOT_TESTED defaults, search and filtering.
- `OfflineGameRepositoryTest` (in-memory Room on Robolectric): seeding, favourites, notes surviving a re-seed.
- `HomeViewModelTest`, `LibraryViewModelTest`, `DiscoverViewModelTest`, `FavoritesViewModelTest`,
  `GameDetailViewModelTest`, `CompatibilityReportViewModelTest`: screen state and actions.
- `GameDetailContentTest` (Compose UI): each launch state shows only real actions (no Play button unless the app is installed).
- `AndroidGameLauncherTest`, `ExternalEmulatorLauncherTest`, `UnsupportedGameHandlerTest`, `DefaultGameLaunchManagerTest`:
  launch/missing/failure paths, the compatibility app missing or unconfigured, history recorded only on a real start.
- `AndroidPlatformAppsTest` (Robolectric PackageManager): installed/missing detection, app listing, standard launcher intent.
- `MigrationTest`: Room v1 → v2 against exported schemas, keeping notes and favourites.

Test fixtures are synthetic and are not measurements of any real device.

## Known limitations

- GL_RENDERER reports the GPU family (e.g. `Mali-G715`) but not the shader-core count (`MC7`).
- Per-core max CPU frequencies come from `/sys/devices/system/cpu/*/cpufreq`. Some Android builds block this
  for apps through SELinux; the UI then shows “Not readable on this device”.
- The Vulkan version comes from `FEATURE_VULKAN_HARDWARE_VERSION`. Querying the Vulkan driver itself would need the NDK.
- Robolectric tests check logic and wiring, not real Pixel 9 values. Check those on the device.
- RetroPlay cannot tell whether a Windows game actually ran inside the compatibility app; the user records that (Phase 7).
