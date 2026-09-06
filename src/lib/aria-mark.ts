/** Shared ARIA mark motion — keep in lockstep with `shared/aria-mark.json`. */
export const ARIA_MARK = {
  assetName: "AriaLogo",
  webPath: "/aria-mark.png",
  sharedPath: "shared/brand/aria-mark.png",
  cropScale: 1.0,
  heroMinimumSize: 90,
  idleBreathHz: 0.28,
  listeningBreathHz: 0.42,
  processingBreathHz: 0.52,
  speakingBreathHz: 0.38,
  idleBreathSeconds: 3.57,
  speakBreathSeconds: 2.63,
  maxHueDegrees: 7,
  maxEdgeUndulation: 0.016,
  breathScale: 0.028,
  corePulseAmount: 0.035,
  stillPose: 1.72,
} as const;

export type AriaMarkState = "idle" | "listening" | "processing" | "speaking";
