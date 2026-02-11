"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Heart,
  Flame,
  Clock,
  Zap,
  AlertTriangle,
  SkipForward,
  ChevronRight,
  Bot,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { Button } from "@/components/ui/button";
import { ExerciseNav } from "./exercise-nav";

const COACHING_MESSAGES = [
  "Slow down the eccentric \u2014 3 seconds on the way down",
  "Heart rate is elevated. Take an extra 30 seconds rest",
  "Last set was easy. Let\u2019s bump up 5lbs",
  "You\u2019re crushing it. Two more reps.",
  "Keep your core braced. Tight through the whole rep.",
  "Control the weight \u2014 don\u2019t let it control you",
  "Good form. Maintain that bar path.",
  "Breathe out on the exertion. Stay in rhythm.",
];

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
}

function getHRZone(hr: number): { zone: number; label: string; color: string } {
  if (hr < 110) return { zone: 1, label: "Zone 1", color: "#71717A" };
  if (hr < 130) return { zone: 2, label: "Zone 2", color: "#3B82F6" };
  if (hr < 150) return { zone: 3, label: "Zone 3", color: "#22C55E" };
  if (hr < 165) return { zone: 4, label: "Zone 4", color: "#FF4D00" };
  return { zone: 5, label: "Zone 5", color: "#EF4444" };
}

export function ActiveWorkoutView() {
  const {
    todayWorkout,
    activeWorkout,
    nextSet,
    nextExercise,
    endWorkout,
  } = useAppStore();

  const [elapsedTime, setElapsedTime] = useState(0);
  const [simulatedHR, setSimulatedHR] = useState(activeWorkout.currentHR || 72);
  const [isResting, setIsResting] = useState(false);
  const [restTimeLeft, setRestTimeLeft] = useState(0);
  const [coachMessageIndex, setCoachMessageIndex] = useState(0);
  const [estimatedCalories, setEstimatedCalories] = useState(0);
  const [showEndConfirm, setShowEndConfirm] = useState(false);

  const restTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const exercises = todayWorkout?.exercises ?? [];
  const currentExercise = exercises[activeWorkout.currentExerciseIndex];

  // Elapsed time counter
  useEffect(() => {
    const interval = setInterval(() => {
      setElapsedTime((prev) => prev + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  // Calorie estimation (rough: ~8-12 cal/min for strength training depending on HR)
  useEffect(() => {
    const interval = setInterval(() => {
      setEstimatedCalories((prev) => {
        const calPerSecond = simulatedHR > 140 ? 0.18 : simulatedHR > 120 ? 0.14 : 0.1;
        return prev + calPerSecond;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [simulatedHR]);

  // HR simulation
  useEffect(() => {
    const interval = setInterval(() => {
      setSimulatedHR((prev) => {
        if (isResting) {
          // HR drops during rest
          const target = 110 + Math.random() * 20;
          return Math.round(prev + (target - prev) * 0.15 + (Math.random() - 0.5) * 4);
        }
        // HR rises during active sets
        const target = 135 + Math.random() * 30;
        return Math.round(prev + (target - prev) * 0.1 + (Math.random() - 0.5) * 6);
      });
    }, 1500);
    return () => clearInterval(interval);
  }, [isResting]);

  // Rest timer countdown
  useEffect(() => {
    if (isResting && restTimeLeft > 0) {
      restTimerRef.current = setInterval(() => {
        setRestTimeLeft((prev) => {
          if (prev <= 1) {
            setIsResting(false);
            if (restTimerRef.current) clearInterval(restTimerRef.current);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    }
    return () => {
      if (restTimerRef.current) clearInterval(restTimerRef.current);
    };
  }, [isResting, restTimeLeft]);

  // Coaching message rotation
  useEffect(() => {
    const interval = setInterval(() => {
      setCoachMessageIndex((prev) => (prev + 1) % COACHING_MESSAGES.length);
    }, 8000);
    return () => clearInterval(interval);
  }, []);

  const handleCompleteSet = useCallback(() => {
    if (!currentExercise) return;

    const isLastSet = activeWorkout.currentSet >= currentExercise.sets;
    const isLastExercise =
      activeWorkout.currentExerciseIndex >= exercises.length - 1;

    if (isLastSet && isLastExercise) {
      // Workout complete
      endWorkout();
      return;
    }

    if (isLastSet) {
      // Move to next exercise
      nextExercise();
      setIsResting(true);
      setRestTimeLeft(currentExercise.restSeconds);
    } else {
      // Next set of current exercise
      nextSet();
      setIsResting(true);
      setRestTimeLeft(currentExercise.restSeconds);
    }
  }, [
    activeWorkout.currentSet,
    activeWorkout.currentExerciseIndex,
    currentExercise,
    exercises.length,
    nextSet,
    nextExercise,
    endWorkout,
  ]);

  const handleSkipExercise = useCallback(() => {
    const isLastExercise =
      activeWorkout.currentExerciseIndex >= exercises.length - 1;
    if (isLastExercise) {
      endWorkout();
    } else {
      nextExercise();
      setIsResting(false);
      setRestTimeLeft(0);
    }
  }, [activeWorkout.currentExerciseIndex, exercises.length, nextExercise, endWorkout]);

  const handleSkipRest = useCallback(() => {
    setIsResting(false);
    setRestTimeLeft(0);
    if (restTimerRef.current) clearInterval(restTimerRef.current);
  }, []);

  const handleEndWorkout = useCallback(() => {
    if (!showEndConfirm) {
      setShowEndConfirm(true);
      setTimeout(() => setShowEndConfirm(false), 3000);
      return;
    }
    endWorkout();
  }, [showEndConfirm, endWorkout]);

  if (!todayWorkout || !currentExercise) return null;

  const hrZone = getHRZone(simulatedHR);
  const isLastSet = activeWorkout.currentSet >= currentExercise.sets;
  const isLastExercise =
    activeWorkout.currentExerciseIndex >= exercises.length - 1;

  // Rest timer ring calculation
  const restProgress = currentExercise.restSeconds > 0
    ? restTimeLeft / currentExercise.restSeconds
    : 0;
  const circumference = 2 * Math.PI * 54;
  const strokeDashoffset = circumference * (1 - restProgress);

  return (
    <div className="flex flex-col h-full min-h-screen bg-[#0A0A0A]">
      {/* Header Bar */}
      <div className="flex items-center justify-between px-5 pt-4 pb-2">
        <div className="flex flex-col">
          <span className="text-sm font-medium text-[#A1A1AA]">
            {todayWorkout.name}
          </span>
          <span className="text-xs text-[#71717A]">
            {todayWorkout.type.charAt(0).toUpperCase() + todayWorkout.type.slice(1)} &middot; {todayWorkout.intensity}
          </span>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5 text-white">
            <Clock className="h-4 w-4 text-[#A1A1AA]" />
            <span className="text-sm font-mono font-medium tabular-nums">
              {formatTime(elapsedTime)}
            </span>
          </div>
          <button
            onClick={handleEndWorkout}
            className={cn(
              "min-h-[44px] min-w-[44px] px-4 rounded-lg text-sm font-semibold transition-colors",
              showEndConfirm
                ? "bg-red-600 text-white"
                : "bg-transparent text-red-500 hover:bg-red-500/10"
            )}
          >
            {showEndConfirm ? "Confirm" : "End"}
          </button>
        </div>
      </div>

      {/* Exercise Navigation */}
      <div className="px-5">
        <ExerciseNav
          exercises={exercises}
          currentIndex={activeWorkout.currentExerciseIndex}
        />
      </div>

      {/* Live Metrics Strip */}
      <div className="flex items-center gap-3 px-5 py-3 overflow-x-auto scrollbar-hide">
        {/* Heart Rate */}
        <motion.div
          className="flex items-center gap-1.5 rounded-full bg-[#141414] border border-[#2A2A2A] px-3 py-2 min-w-fit"
          animate={{ scale: [1, 1.03, 1] }}
          transition={{ duration: 1, repeat: Infinity, ease: "easeInOut" }}
        >
          <Heart className="h-4 w-4 text-red-500 fill-red-500" />
          <span className="text-sm font-bold text-white tabular-nums">
            {simulatedHR}
          </span>
          <span className="text-xs text-[#71717A]">bpm</span>
        </motion.div>

        {/* Calories */}
        <div className="flex items-center gap-1.5 rounded-full bg-[#141414] border border-[#2A2A2A] px-3 py-2 min-w-fit">
          <Flame className="h-4 w-4 text-[#FF4D00]" />
          <span className="text-sm font-bold text-white tabular-nums">
            {Math.round(estimatedCalories)}
          </span>
          <span className="text-xs text-[#71717A]">cal</span>
        </div>

        {/* Elapsed Time */}
        <div className="flex items-center gap-1.5 rounded-full bg-[#141414] border border-[#2A2A2A] px-3 py-2 min-w-fit">
          <Clock className="h-4 w-4 text-[#3B82F6]" />
          <span className="text-sm font-bold text-white tabular-nums">
            {formatTime(elapsedTime)}
          </span>
        </div>

        {/* Intensity Zone */}
        <div
          className="flex items-center gap-1.5 rounded-full px-3 py-2 min-w-fit"
          style={{
            backgroundColor: `${hrZone.color}15`,
            borderColor: `${hrZone.color}40`,
            borderWidth: 1,
          }}
        >
          <Zap className="h-4 w-4" style={{ color: hrZone.color }} />
          <span
            className="text-sm font-bold"
            style={{ color: hrZone.color }}
          >
            {hrZone.label}
          </span>
        </div>
      </div>

      {/* Scrollable content area */}
      <div className="flex-1 overflow-y-auto px-5 pb-4">
        <AnimatePresence mode="wait">
          {isResting ? (
            /* Rest Timer */
            <motion.div
              key="rest-timer"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ duration: 0.3 }}
              className="flex flex-col items-center justify-center py-6"
            >
              <span className="text-sm font-medium text-[#A1A1AA] mb-4 uppercase tracking-wider">
                Rest
              </span>

              {/* Circular Timer */}
              <div className="relative flex items-center justify-center w-[140px] h-[140px] mb-5">
                <svg
                  className="absolute inset-0 -rotate-90"
                  width="140"
                  height="140"
                  viewBox="0 0 120 120"
                >
                  {/* Background ring */}
                  <circle
                    cx="60"
                    cy="60"
                    r="54"
                    fill="none"
                    stroke="#2A2A2A"
                    strokeWidth="6"
                  />
                  {/* Progress ring */}
                  <motion.circle
                    cx="60"
                    cy="60"
                    r="54"
                    fill="none"
                    stroke="#FF4D00"
                    strokeWidth="6"
                    strokeLinecap="round"
                    strokeDasharray={circumference}
                    strokeDashoffset={strokeDashoffset}
                    style={{
                      filter: "drop-shadow(0 0 6px rgba(255, 77, 0, 0.5))",
                    }}
                  />
                </svg>
                <span className="text-4xl font-bold text-white tabular-nums">
                  {restTimeLeft}
                </span>
              </div>

              <span className="text-sm text-[#71717A] mb-6">
                Next: {isLastSet
                  ? (isLastExercise
                    ? "Workout Complete"
                    : exercises[activeWorkout.currentExerciseIndex + 1]?.name ?? "Done")
                  : `Set ${activeWorkout.currentSet} of ${currentExercise.sets}`}
              </span>

              <Button
                variant="secondary"
                size="lg"
                onClick={handleSkipRest}
                className="min-h-[52px] min-w-[160px] text-base"
              >
                <SkipForward className="h-5 w-5" />
                Skip Rest
              </Button>
            </motion.div>
          ) : (
            /* Current Exercise Card */
            <motion.div
              key={`exercise-${activeWorkout.currentExerciseIndex}-${activeWorkout.currentSet}`}
              initial={{ opacity: 0, x: 30 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -30 }}
              transition={{ duration: 0.3 }}
              className="mt-2"
            >
              <div className="rounded-2xl bg-[#141414] border border-[#2A2A2A] p-6">
                {/* Set indicator */}
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-[#FF4D00]">
                    Set {activeWorkout.currentSet} of {currentExercise.sets}
                  </span>
                  <span className="text-xs text-[#71717A]">
                    Exercise {activeWorkout.currentExerciseIndex + 1}/{exercises.length}
                  </span>
                </div>

                {/* Exercise name */}
                <h2 className="text-2xl font-bold text-white mb-3 leading-tight">
                  {currentExercise.name}
                </h2>

                {/* Weight and reps */}
                <div className="flex items-baseline gap-2 mb-2">
                  {currentExercise.weight && (
                    <>
                      <span className="text-3xl font-bold text-white tabular-nums">
                        {currentExercise.weight}
                      </span>
                      <span className="text-lg text-[#A1A1AA]">lbs</span>
                      <span className="text-2xl text-[#71717A] mx-1">&times;</span>
                    </>
                  )}
                  <span className="text-3xl font-bold text-white tabular-nums">
                    {currentExercise.reps}
                  </span>
                  <span className="text-lg text-[#A1A1AA]">reps</span>
                </div>

                {/* Rest info */}
                <div className="flex items-center gap-1.5 mb-3">
                  <Clock className="h-3.5 w-3.5 text-[#71717A]" />
                  <span className="text-xs text-[#71717A]">
                    {currentExercise.restSeconds}s rest between sets
                  </span>
                </div>

                {/* Notes */}
                {currentExercise.notes && (
                  <p className="text-sm italic text-[#A1A1AA] mt-3 pt-3 border-t border-[#2A2A2A]">
                    &ldquo;{currentExercise.notes}&rdquo;
                  </p>
                )}
              </div>

              {/* Action Buttons */}
              <div className="mt-5 space-y-3">
                {/* Complete Set - Primary large button */}
                <Button
                  variant="default"
                  size="lg"
                  onClick={handleCompleteSet}
                  className="w-full min-h-[56px] text-lg font-bold rounded-xl"
                >
                  {isLastSet && isLastExercise
                    ? "Finish Workout"
                    : isLastSet
                      ? "Complete \u00b7 Next Exercise"
                      : "Complete Set"}
                  <ChevronRight className="h-5 w-5 ml-1" />
                </Button>

                {/* Secondary actions row */}
                <div className="flex items-center gap-3">
                  <button
                    onClick={handleSkipExercise}
                    className="flex-1 min-h-[44px] rounded-lg text-sm font-medium text-[#A1A1AA] hover:text-white hover:bg-[#1A1A1A] transition-colors"
                  >
                    Skip Exercise
                  </button>
                  <button
                    className="min-h-[44px] min-w-[44px] flex items-center justify-center gap-2 rounded-lg text-sm text-[#71717A] hover:text-[#EF4444] hover:bg-[#1A1A1A] transition-colors px-3"
                    onClick={() => {
                      // Pain/discomfort logging placeholder
                    }}
                  >
                    <AlertTriangle className="h-4 w-4" />
                    <span className="text-xs">Log Pain</span>
                  </button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* AI Coach Bar - Fixed at bottom */}
      <div className="px-5 pb-5 pt-2">
        <div className="rounded-xl bg-[#1A1A1A] border border-[#2A2A2A] p-4">
          <div className="flex items-start gap-3">
            <div className="flex-shrink-0 mt-0.5 w-8 h-8 rounded-full bg-[#FF4D00]/10 flex items-center justify-center">
              <Bot className="h-4 w-4 text-[#FF4D00]" />
            </div>
            <div className="flex-1 min-h-[40px] flex items-center">
              <AnimatePresence mode="wait">
                <motion.p
                  key={coachMessageIndex}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -8 }}
                  transition={{ duration: 0.4 }}
                  className="text-sm text-[#A1A1AA] leading-relaxed"
                >
                  {COACHING_MESSAGES[coachMessageIndex]}
                </motion.p>
              </AnimatePresence>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
