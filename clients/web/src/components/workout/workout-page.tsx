"use client";

import { motion, AnimatePresence } from "framer-motion";
import { Dumbbell, Play, Calendar } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { Button } from "@/components/ui/button";
import { ActiveWorkoutView } from "./active-workout-view";

export function WorkoutPage() {
  const { todayWorkout, activeWorkout, startWorkout } = useAppStore();

  return (
    <AnimatePresence mode="wait">
      {activeWorkout.isActive ? (
        <motion.div
          key="active-workout"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.3 }}
          className="h-full"
        >
          <ActiveWorkoutView />
        </motion.div>
      ) : (
        <motion.div
          key="workout-idle"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -20 }}
          transition={{ duration: 0.35 }}
          className="flex flex-col items-center justify-center min-h-[100dvh] bg-[#0A0A0A] px-6"
        >
          {todayWorkout ? (
            <div className="flex flex-col items-center w-full max-w-sm">
              {/* Icon */}
              <motion.div
                className="w-20 h-20 rounded-2xl bg-[#FF4D00]/10 flex items-center justify-center mb-6"
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: "spring", stiffness: 300 }}
              >
                <Dumbbell className="h-10 w-10 text-[#FF4D00]" />
              </motion.div>

              {/* Title */}
              <motion.h2
                className="text-2xl font-bold text-white text-center mb-2"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.15 }}
              >
                {todayWorkout.name}
              </motion.h2>

              {/* Subtitle */}
              <motion.p
                className="text-sm text-[#A1A1AA] text-center mb-2"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.2 }}
              >
                {todayWorkout.exercises.length} exercises &middot;{" "}
                {todayWorkout.duration} min &middot;{" "}
                {todayWorkout.intensity} intensity
              </motion.p>

              {/* Exercise preview list */}
              <motion.div
                className="w-full rounded-xl bg-[#141414] border border-[#2A2A2A] p-4 mb-8 mt-4"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.25 }}
              >
                {todayWorkout.exercises.map((exercise, index) => (
                  <div
                    key={exercise.id}
                    className="flex items-center justify-between py-2.5 border-b border-[#2A2A2A] last:border-b-0"
                  >
                    <div className="flex items-center gap-3">
                      <span className="text-xs font-bold text-[#71717A] w-5 text-right">
                        {index + 1}
                      </span>
                      <span className="text-sm text-white">
                        {exercise.name}
                      </span>
                    </div>
                    <span className="text-xs text-[#71717A]">
                      {exercise.sets} &times; {exercise.reps}
                    </span>
                  </div>
                ))}
              </motion.div>

              {/* Start Button */}
              <motion.div
                className="w-full"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.35 }}
              >
                <Button
                  variant="default"
                  size="lg"
                  onClick={startWorkout}
                  className="w-full min-h-[56px] text-lg font-bold rounded-xl"
                >
                  <Play className="h-5 w-5 mr-2 fill-current" />
                  Start Workout
                </Button>
              </motion.div>
            </div>
          ) : (
            /* No workout planned state */
            <div className="flex flex-col items-center w-full max-w-sm">
              <motion.div
                className="w-20 h-20 rounded-2xl bg-[#1A1A1A] border border-[#2A2A2A] flex items-center justify-center mb-6"
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: "spring", stiffness: 300 }}
              >
                <Calendar className="h-10 w-10 text-[#71717A]" />
              </motion.div>

              <motion.h2
                className="text-xl font-bold text-white text-center mb-2"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.15 }}
              >
                No Workout Planned
              </motion.h2>

              <motion.p
                className="text-sm text-[#A1A1AA] text-center mb-8 leading-relaxed"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.2 }}
              >
                You don&apos;t have a workout scheduled for today.
                <br />
                Chat with your AI coach to plan one.
              </motion.p>

              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.3 }}
              >
                <Button
                  variant="secondary"
                  size="lg"
                  className="min-h-[52px] px-8"
                >
                  Talk to Coach
                </Button>
              </motion.div>
            </div>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
