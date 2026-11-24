# Pull-Up Coach

Android app that counts pull-ups and chin-ups from a phone clip, grades each
rep's range of motion, and lets you replay the clip with a skeleton overlay —
no API key required.

- **App display name:** Pull-Up Coach
- **Package ID:** `dev.visiondemos.pullups`
- **Platform:** Android only (minSdk 24)
- **Input:** system camera ("Record") + gallery only — no in-app camera UI
- **Pose estimation:** VLM Run gateway, anonymous tier (`api_key = "vlmrun"`), no account
- **Output:** rep count, full/partial ROM, pull time, displacement chart, replay with skeleton overlay. No MP4 export.
- **Analysis ported from Python** (`pull_ups/src/reps.py`, `rom.py`) and validated 15/15 against golden fixtures.

## Build & install

Requires the Flutter SDK and an Android SDK (SDK 36 used here).

```bash
cd vision-demos/pullup_app
flutter pub get
flutter build apk --release
```

The APK is produced at `build/app/outputs/flutter-apk/app-release.apk` and is
signed with the debug key, so you can install it directly:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

No physical device is needed for the build, but you need one (or an emulator)
to record or pick clips and run the analysis.

## How it works

1. **Home** — choose pull-up or chin-up mode, then record via the system camera
   or choose a clip from the gallery.
2. **Trim** — pick the part of the clip to count. The clip is trimmed and
   re-encoded on the phone to 720p / 30 fps H.264 (Media3 Transformer), so only
   a small copy is uploaded.
3. **Analyse** — the trimmed clip is sent base64 to the VLM Run gateway for
   pose estimation. The app counts reps, grades range of motion against the
   clip's own deepest hang, and saves everything on disk.
4. **Results** — rep count, full/partial ROM tally, mean pull time, fastest
   rep, displacement chart with a marker per rep, and a per-rep table.
5. **Replay** — play the saved clip with the skeleton overlaid, live rep count,
   phase (dead hang / pulling / top / lowering), and elbow angle. 0.25× / 0.5× /
   1× speed. No network needed for a second look.

## Anonymous tier

With no gateway key in Settings, the app uses the published anonymous tier:

- 10 requests / min, 30 / hour, 100 / day per IP
- Up to 900 frames per clip (the app trims to ≤28 s at 30 fps)

Limits apply per public IP, so a whole network shares them. Add your own key in
Settings to bypass.

## Project layout

```
lib/
  main.dart           App entry + theme
  core/
    config.dart       Lift presets + pipeline constants
    gateway.dart      VLM Run gateway call (cancelable)
    mathx.dart        NumPy primitives ported exactly
    models.dart       Kpt, Person, PoseFrame, Rep, Grade, Analysis
    orientation.dart  Head-above-hips rotation inference
    pipeline.dart     Transcode -> gateway -> analyze -> save
    prefs.dart          shared_preferences (mode + api key)
    rom.dart          Grader (full / partial ROM)
    signal.dart       RepAnalyzer (displacement + counting)
    store.dart        RunStore (poses.json / analysis.json / meta.json)
    video_toolkit.dart MethodChannel -> Kotlin probe/transcode
  ui/
    home_page.dart    Mode, Record/Gallery, history
    trim_page.dart    Clip trimmer + preview
    analyzing_page.dart Progress + cancellation
    results_page.dart Count, stats, chart, rep table
    replay_page.dart  Video + skeleton overlay + live panel
    settings_page.dart Key, tier limits, clear history
    widgets/
      displacement_chart.dart
      pose_overlay.dart
    theme.dart        Dark palette + shared widgets
    format.dart       Seconds/degrees/bytes formatting
android/
  app/src/main/kotlin/dev/visiondemos/pullups/
    MainActivity.kt   FlutterActivity + MethodChannel
    VideoToolkit.kt   Media3 trim/transcode (720p/30 H.264, HDR->SDR)
    VideoProbe.kt     MediaMetadataRetriever probe
tools/
  gen_fixtures.py     Regenerates test/fixtures from pull_ups (read-only)
test/
  golden_test.dart    18 tests, 15 fixtures ported 1:1 from Python
```

## Notes

- Existing Python demos under `vision-demos/pull_ups/` are never modified.
- The original video never leaves the phone — only the trimmed 720p copy is
  uploaded for pose estimation.
- Saved runs live in the app's support directory (`runs/`); clearing history
  deletes them from the phone.
- Rotation metadata is not trusted: the app infers keypoint orientation from
  head-above-hips geometry, because a server-side decoder may ignore the tag.
