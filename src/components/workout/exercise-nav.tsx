"use client";

import { motion } from "framer-motion";
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Exercise } from "@/types";

interface ExerciseNavProps {
  exercises: Exercise[];
  currentIndex: number;
}

export function ExerciseNav({ exercises, currentIndex }: ExerciseNavProps) {
  return (
    <div className="flex items-center gap-2 overflow-x-auto px-1 py-3 scrollbar-hide">
      {exercises.map((exercise, index) => {
        const isCompleted = index < currentIndex;
        const isCurrent = index === currentIndex;
        const isUpcoming = index > currentIndex;

        return (
          <div key={exercise.id} className="flex items-center gap-2">
            <motion.div
              className={cn(
                "relative flex items-center justify-center rounded-full transition-colors",
                "min-w-[36px] min-h-[36px]",
                isCurrent &&
                  "bg-ember shadow-[0_0_12px_rgba(255,77,0,0.4)]",
                isCompleted && "bg-ember/20",
                isUpcoming && "bg-surface-elevated border border-border"
              )}
              initial={false}
              animate={
                isCurrent
                  ? { scale: [1, 1.1, 1] }
                  : { scale: 1 }
              }
              transition={
                isCurrent
                  ? { duration: 1.5, repeat: Infinity, ease: "easeInOut" }
                  : { duration: 0.2 }
              }
            >
              {isCompleted ? (
                <Check className="h-4 w-4 text-ember" />
              ) : (
                <span
                  className={cn(
                    "text-xs font-bold",
                    isCurrent && "text-text-primary",
                    isUpcoming && "text-text-tertiary"
                  )}
                >
                  {index + 1}
                </span>
              )}
            </motion.div>

            {/* Connector line between dots */}
            {index < exercises.length - 1 && (
              <div
                className={cn(
                  "h-[2px] w-4 rounded-full",
                  index < currentIndex ? "bg-ember/40" : "bg-border"
                )}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
