"use client";

import { motion } from "framer-motion";
import { Clock, Zap, Dumbbell, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import type { WorkoutPlan } from "@/types";

interface TodayPlanCardProps {
  workout: WorkoutPlan;
  onStart: () => void;
  onChangePlan: () => void;
}

function IntensityDot({ intensity }: { intensity: string }) {
  const color =
    intensity === "max"
      ? "bg-danger"
      : intensity === "high"
        ? "bg-ember"
        : intensity === "moderate"
          ? "bg-warning"
          : "bg-success";

  return <span className={cn("inline-block h-1.5 w-1.5 rounded-full", color)} />;
}

function capitalizeFirst(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

export function TodayPlanCard({ workout, onStart, onChangePlan }: TodayPlanCardProps) {
  const previewExercises = workout.exercises.slice(0, 3);

  return (
    <motion.div
      className="rounded-2xl bg-surface p-5"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.2, ease: "easeOut" }}
    >
      {/* Header label */}
      <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-3">
        Today&apos;s Plan
      </p>

      {/* Workout name */}
      <h2 className="text-2xl font-bold text-text-primary mb-3">
        {workout.name}
      </h2>

      {/* Info pills row */}
      <div className="flex flex-wrap items-center gap-2 mb-5">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-elevated px-3 py-1.5 text-xs font-medium text-text-secondary">
          <Dumbbell size={13} className="text-text-tertiary" />
          {capitalizeFirst(workout.type)}
        </span>
        <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-elevated px-3 py-1.5 text-xs font-medium text-text-secondary">
          <Clock size={13} className="text-text-tertiary" />
          ~{workout.duration} min
        </span>
        <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-elevated px-3 py-1.5 text-xs font-medium text-text-secondary">
          <IntensityDot intensity={workout.intensity} />
          <Zap size={13} className="text-text-tertiary" />
          {capitalizeFirst(workout.intensity)}
        </span>
      </div>

      {/* Exercise preview */}
      <div className="mb-5 space-y-2.5">
        {previewExercises.map((exercise, index) => (
          <motion.div
            key={exercise.id}
            className="flex items-center justify-between"
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.4 + index * 0.1, duration: 0.3 }}
          >
            <div className="flex items-center gap-3">
              <span className="flex h-6 w-6 items-center justify-center rounded-md bg-surface-elevated text-[10px] font-bold text-text-tertiary">
                {index + 1}
              </span>
              <span className="text-sm text-text-primary">{exercise.name}</span>
            </div>
            <span className="text-xs text-text-tertiary">
              {exercise.sets} x {exercise.reps}
            </span>
          </motion.div>
        ))}
        {workout.exercises.length > 3 && (
          <p className="pl-9 text-xs text-text-tertiary">
            +{workout.exercises.length - 3} more exercises
          </p>
        )}
      </div>

      {/* Start Workout CTA */}
      <motion.button
        onClick={onStart}
        className={cn(
          "w-full rounded-xl bg-ember py-3.5 px-6",
          "text-base font-semibold text-white",
          "glow-ember",
          "flex items-center justify-center gap-2"
        )}
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.97 }}
        transition={{ type: "spring", stiffness: 400, damping: 17 }}
      >
        Start Workout
        <ChevronRight size={18} />
      </motion.button>

      {/* Change plan link */}
      <motion.button
        onClick={onChangePlan}
        className={cn(
          "mt-3 w-full text-center text-xs font-medium",
          "text-text-tertiary hover:text-text-secondary transition-colors"
        )}
        whileTap={{ scale: 0.97 }}
      >
        Change Plan
      </motion.button>
    </motion.div>
  );
}
