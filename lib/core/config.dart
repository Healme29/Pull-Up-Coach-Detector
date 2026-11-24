/// The settings that decide what a result means, ported from
/// `pull_ups/config.py` and `chin_ups/config.py`.
///
/// Only the constants the analysis actually reads are here. Anything that
/// belongs to rendering the CLI video (panel fonts, credits) is not.
library;

enum LiftMode {
  pullUp('Pull-up'),
  chinUp('Chin-up');

  const LiftMode(this.label);

  final String label;
}

/// One athlete's set of analysis constants.
class AnalysisConfig {
  const AnalysisConfig({
    required this.mode,
    required this.torsoJoints,
    required this.handJoints,
    required this.headJoints,
    required this.headMinScore,
    required this.referenceToHands,
    required this.handOffBarTolerance,
    required this.smoothMedianFrames,
    required this.smoothMeanFrames,
    required this.baselinePercentile,
    required this.repPeakFraction,
    required this.repResetFraction,
    required this.repPeakFractionCalibrated,
    required this.repMinFlexionFraction,
    required this.requireHeadAboveHands,
    required this.repMetric,
    required this.repOnsetMethod,
    required this.repOnsetVelocityFraction,
    required this.repOnsetFraction,
    required this.gradeRom,
    required this.armJoints,
    required this.romHangToleranceDegrees,
    required this.romClearanceTorsoFraction,
    required this.romHangElbowDegrees,
    required this.romSampleFrames,
  });

  final LiftMode mode;

  // Signal
  final List<String> torsoJoints;
  final List<String> handJoints;
  final List<String> headJoints;
  final double headMinScore;
  final bool referenceToHands;
  final double handOffBarTolerance;
  final int smoothMedianFrames;
  final int smoothMeanFrames;
  final double baselinePercentile;

  // Rep counting
  final double repPeakFraction;
  final double repResetFraction;
  final double repPeakFractionCalibrated;
  final double repMinFlexionFraction;
  final bool requireHeadAboveHands;
  final String repMetric;
  final String repOnsetMethod;
  final double repOnsetVelocityFraction;
  final double repOnsetFraction;

  // Range of motion
  final bool gradeRom;
  final List<List<String>> armJoints;
  final double romHangToleranceDegrees;
  final double romClearanceTorsoFraction;
  final double romHangElbowDegrees;
  final int romSampleFrames;

  /// The two presets, matching the Pull-ups and Chin-ups tabs of the web app.
  ///
  /// Pull-ups: every pull counts and range of motion is graded, so a half rep
  /// shows up as partial rather than disappearing.
  /// Chin-ups: a rep only counts when the chin clears the bar
  /// (`REQUIRE_HEAD_ABOVE_HANDS`), and there is no ROM grading.
  static const pullUp = AnalysisConfig(
    mode: LiftMode.pullUp,
    torsoJoints: ['left_shoulder', 'right_shoulder', 'left_hip', 'right_hip'],
    handJoints: ['left_wrist', 'right_wrist'],
    headJoints: ['nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear'],
    headMinScore: 0.3,
    referenceToHands: true,
    handOffBarTolerance: 0.05,
    smoothMedianFrames: 5,
    smoothMeanFrames: 7,
    baselinePercentile: 10,
    repPeakFraction: 0.60,
    repResetFraction: 0.30,
    repPeakFractionCalibrated: 0.35,
    repMinFlexionFraction: 0.35,
    requireHeadAboveHands: false,
    repMetric: 'moving',
    repOnsetMethod: 'velocity',
    repOnsetVelocityFraction: 0.10,
    repOnsetFraction: 0.05,
    gradeRom: true,
    armJoints: [
      ['left_shoulder', 'left_elbow', 'left_wrist'],
      ['right_shoulder', 'right_elbow', 'right_wrist'],
    ],
    romHangToleranceDegrees: 12.5,
    romClearanceTorsoFraction: 0.18,
    romHangElbowDegrees: 150.0,
    romSampleFrames: 5,
  );

  static const chinUp = AnalysisConfig(
    mode: LiftMode.chinUp,
    torsoJoints: ['left_shoulder', 'right_shoulder', 'left_hip', 'right_hip'],
    handJoints: ['left_wrist', 'right_wrist'],
    headJoints: ['left_eye', 'right_eye'],
    headMinScore: 0.3,
    referenceToHands: true,
    handOffBarTolerance: 0.05,
    smoothMedianFrames: 5,
    smoothMeanFrames: 7,
    baselinePercentile: 10,
    repPeakFraction: 0.60,
    repResetFraction: 0.30,
    repPeakFractionCalibrated: 0.35,
    repMinFlexionFraction: 0.35,
    requireHeadAboveHands: true,
    repMetric: 'moving',
    repOnsetMethod: 'velocity',
    repOnsetVelocityFraction: 0.10,
    repOnsetFraction: 0.05,
    gradeRom: false,
    armJoints: [
      ['left_shoulder', 'left_elbow', 'left_wrist'],
      ['right_shoulder', 'right_elbow', 'right_wrist'],
    ],
    romHangToleranceDegrees: 12.5,
    romClearanceTorsoFraction: 0.18,
    romHangElbowDegrees: 150.0,
    romSampleFrames: 5,
  );

  static AnalysisConfig forMode(LiftMode mode) =>
      mode == LiftMode.chinUp ? chinUp : pullUp;
}

/// Fixed pipeline settings: the upload is normalised before it is sent, so the
/// model sees a 720p, 30 fps clip no matter what the phone recorded.
class PipelineConfig {
  PipelineConfig._();

  /// The model caps a video pose call at 900 frames on the anonymous tier.
  static const int anonymousMaxFrames = 900;

  /// The frame rate the app normalises every clip to.
  static const double inferenceFps = 30.0;

  /// The height the model is fed, matching `INFERENCE_HEIGHT = 720` in the
  /// web app. The phone's 4K original is never uploaded.
  static const int inferenceHeight = 720;

  /// A little under 900 frames at 30 fps, so the last frame is never dropped.
  static const double maxClipSeconds = 28.0;

  static const String gatewayBaseUrl = 'https://gateway.vlm.run/v1/openai';

  /// The gateway's documented anonymous spelling. No account needed.
  static const String anonymousKey = 'vlmrun';

  static const String poseModel = 'usyd-community/vitpose-plus-large';

  /// Anonymous limits, as published on the gateway's rate-limits page.
  static const String anonymousLimits = '10/min, 30/hr, 100/day per IP';

  static const Duration requestTimeout = Duration(minutes: 30);

  static int framesFor(double seconds) =>
      (seconds * inferenceFps).round().clamp(1, anonymousMaxFrames);

  static double maxClipFrames() => maxClipSeconds;
}
