"use client";

import type { ReactNode } from "react";
import { MotionConfig } from "framer-motion";

/**
 * App-wide Reduce Motion gate for every `motion` / `AnimatePresence` child.
 *
 * Verified in framer-motion@13.1.1 (do not assume from docs alone):
 * - `MotionConfigContext` defaults `reducedMotion` to `"never"`
 *   (`node_modules/framer-motion/dist/es/context/MotionConfigContext.mjs`).
 * - `useReducedMotionConfig()` returns `false` when the config is `"never"`,
 *   so OS `prefers-reduced-motion` is ignored unless a parent overrides it
 *   (`node_modules/framer-motion/dist/es/utils/reduced-motion/use-reduced-motion-config.mjs`).
 * - `reducedMotion="user"` forwards the OS setting to the whole tree.
 * Root `layout.tsx` is a Server Component, so this client wrapper is required.
 */
export function MotionConfigProvider({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
