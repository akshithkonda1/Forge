"use client";

import { useCallback, useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { ARIA_CINEMATIC_LINES } from "@/lib/aria-onboarding";
import { AriaOrb } from "./aria-companion";

interface WelcomeScreenProps {
  onNext: () => void;
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  const [lineIndex, setLineIndex] = useState(0);
  const [typed, setTyped] = useState("");
  const [doneTyping, setDoneTyping] = useState(false);

  const fullLine = ARIA_CINEMATIC_LINES[lineIndex];
  const isLast = lineIndex >= ARIA_CINEMATIC_LINES.length - 1;
  const progress = (lineIndex + 1) / ARIA_CINEMATIC_LINES.length;

  useEffect(() => {
    setTyped("");
    setDoneTyping(false);
    let i = 0;
    const id = window.setInterval(() => {
      i += 1;
      setTyped(fullLine.slice(0, i));
      if (i >= fullLine.length) {
        window.clearInterval(id);
        setDoneTyping(true);
      }
    }, 22);
    return () => window.clearInterval(id);
  }, [fullLine, lineIndex]);

  const advance = useCallback(() => {
    if (!isLast) {
      setLineIndex((n) => n + 1);
      return;
    }
    onNext();
  }, [isLast, onNext]);

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden">
      {/* Ambient aurora */}
      <div className="pointer-events-none fixed inset-0">
        <div
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 60% 45% at 50% 32%, rgba(168,85,247,0.16) 0%, transparent 70%)",
          }}
        />
        <div
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 40% 30% at 70% 60%, rgba(255,77,0,0.10) 0%, transparent 65%)",
          }}
        />
      </div>

      <div className="relative z-10 flex flex-1 flex-col px-6 pb-8 pt-6">
        <div className="flex justify-end">
          <button
            type="button"
            onClick={onNext}
            className="rounded-full border border-border bg-surface/70 px-3.5 py-1.5 text-xs font-bold text-text-muted transition hover:text-text-secondary"
          >
            Skip intro
          </button>
        </div>

        <div className="flex flex-1 flex-col items-center justify-center text-center">
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.7, ease: [0.25, 0.46, 0.45, 0.94] }}
            className="mb-8"
          >
            <AriaOrb mood="focused" size={148} speaking={!doneTyping} />
          </motion.div>

          <motion.p
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15 }}
            className="mb-2 text-[11px] font-black uppercase tracking-[0.28em] text-ember"
          >
            FORGE × ARIA
          </motion.p>
          <motion.h1
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.25 }}
            className="mb-8 max-w-sm text-3xl font-black tracking-tight text-text-primary"
            style={{ fontFamily: "var(--font-display)" }}
          >
            Meet your intelligence layer
          </motion.h1>

          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.35 }}
            className="w-full max-w-md rounded-2xl border border-ember/30 bg-surface/90 p-5 text-left shadow-[0_0_40px_rgba(255,77,0,0.12)]"
          >
            <div className="mb-3 flex items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <span
                  className={cn(
                    "h-2 w-2 rounded-full bg-ember",
                    !doneTyping && "animate-pulse"
                  )}
                />
                <span className="text-[10px] font-black uppercase tracking-[0.16em] text-text-muted">
                  ARIA
                </span>
              </div>
              <span className="font-mono text-[11px] font-bold text-text-muted">
                {lineIndex + 1}/{ARIA_CINEMATIC_LINES.length}
              </span>
            </div>

            <AnimatePresence mode="wait">
              <motion.p
                key={lineIndex}
                className="min-h-[4.5rem] text-base font-medium leading-relaxed text-text-primary"
              >
                {typed}
                {!doneTyping && (
                  <span className="ml-0.5 inline-block h-4 w-0.5 translate-y-0.5 bg-ember animate-pulse" />
                )}
              </motion.p>
            </AnimatePresence>

            <div className="mt-4 h-0.5 overflow-hidden rounded-full bg-white/10">
              <motion.div
                className="h-full rounded-full bg-gradient-to-r from-ember to-ember-light"
                animate={{ width: `${progress * 100}%` }}
                transition={{ duration: 0.35 }}
              />
            </div>
          </motion.div>
        </div>

        <div className="mx-auto w-full max-w-md space-y-3">
          {!isLast && (
            <button
              type="button"
              onClick={onNext}
              className="w-full py-2 text-sm font-semibold text-text-muted transition hover:text-text-secondary"
            >
              Skip intro
            </button>
          )}
          <motion.button
            type="button"
            onClick={advance}
            className={cn(
              "w-full rounded-xl px-8 py-4 text-lg font-semibold text-white",
              "focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            )}
            style={{
              background: "linear-gradient(135deg, #FF4D00, #FF6B2B)",
            }}
            whileHover={{ scale: 1.02, boxShadow: "0 0 30px rgba(255,77,0,0.4)" }}
            whileTap={{ scale: 0.98 }}
          >
            {isLast ? "Continue with ARIA" : "Next"}
          </motion.button>
        </div>
      </div>
    </div>
  );
}
