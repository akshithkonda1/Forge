"use client";

import * as React from "react";
import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { ChevronDown, Clock, Dumbbell, Play } from "lucide-react";

interface WorkoutExercise {
  name: string;
  sets: number;
  reps: string | number;
}

interface WorkoutCardProps {
  name: string;
  duration: number;
  exercises: WorkoutExercise[];
}

export function WorkoutCard({ name, duration, exercises }: WorkoutCardProps) {
  const [expanded, setExpanded] = useState(false);

  return (
    <motion.div
      className={cn(
        "overflow-hidden rounded-xl border border-border bg-surface",
        "border-l-[3px] border-l-ember"
      )}
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.3 }}
    >
      {/* Header */}
      <div className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex-1">
            <h4 className="text-sm font-semibold text-text-primary">{name}</h4>
            <div className="mt-1.5 flex items-center gap-3">
              <span className="flex items-center gap-1 text-xs text-text-tertiary">
                <Clock className="h-3 w-3" />
                {duration} min
              </span>
              <span className="flex items-center gap-1 text-xs text-text-tertiary">
                <Dumbbell className="h-3 w-3" />
                {exercises.length} exercises
              </span>
            </div>
          </div>
        </div>

        {/* Expand toggle */}
        <button
          onClick={() => setExpanded(!expanded)}
          className="mt-3 flex w-full items-center justify-between rounded-lg bg-surface-elevated px-3 py-2 text-xs text-text-secondary transition-colors hover:text-text-primary"
        >
          <span>{expanded ? "Hide exercises" : "View exercises"}</span>
          <motion.div
            animate={{ rotate: expanded ? 180 : 0 }}
            transition={{ duration: 0.2 }}
          >
            <ChevronDown className="h-3.5 w-3.5" />
          </motion.div>
        </button>
      </div>

      {/* Expandable exercise list */}
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25, ease: "easeInOut" }}
            className="overflow-hidden"
          >
            <div className="border-t border-border px-4 py-3">
              <div className="space-y-2.5">
                {exercises.map((exercise, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between"
                  >
                    <div className="flex items-center gap-2.5">
                      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-ember/10 text-[10px] font-medium text-ember">
                        {index + 1}
                      </span>
                      <span className="text-xs text-text-primary">
                        {exercise.name}
                      </span>
                    </div>
                    <span className="text-xs text-text-tertiary">
                      {exercise.sets} x {exercise.reps}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Start workout button */}
      <div className="border-t border-border p-3">
        <motion.button
          className="flex w-full items-center justify-center gap-2 rounded-xl bg-ember py-2.5 text-sm font-semibold text-white shadow-[0_0_20px_rgba(255,77,0,0.25)]"
          whileTap={{ scale: 0.97 }}
          whileHover={{ scale: 1.01 }}
          transition={{ type: "spring", stiffness: 400, damping: 17 }}
        >
          <Play className="h-3.5 w-3.5" fill="currentColor" />
          Start This Workout
        </motion.button>
      </div>
    </motion.div>
  );
}
