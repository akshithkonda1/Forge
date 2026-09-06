import contract from "../../shared/aria-mark.json";

/** Shared ARIA mark motion — keep in lockstep with `AriaSigilGeometry`. */
export const ARIA_MARK = contract;

export type AriaMarkState = "idle" | "listening" | "processing" | "speaking";
