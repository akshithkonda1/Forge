"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useToast } from "@/stores/useToast";

export function ToastHost() {
  const message = useToast((s) => s.message);

  return (
    <div className="pointer-events-none fixed inset-x-0 top-[max(0.75rem,env(safe-area-inset-top))] z-[90] flex justify-center px-4">
      <AnimatePresence>
        {message && (
          <motion.div
            role="status"
            aria-live="polite"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="pointer-events-auto max-w-sm rounded-full border border-ember/30 bg-surface/95 px-4 py-2 text-center text-xs font-medium text-text-primary shadow-[0_8px_32px_rgba(255,77,0,0.18)] backdrop-blur-xl"
          >
            {message}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
