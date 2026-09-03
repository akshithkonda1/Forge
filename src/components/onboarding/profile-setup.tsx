"use client";

import { useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import type { FitnessGoal, ExperienceLevel, WorkoutType } from "@/types";
import { whisperForStep } from "@/lib/aria-onboarding";
import AriaCompanion from "./aria-companion";

interface ProfileSetupProps {
  onNext: () => void;
  onBack?: () => void;
}

const fitnessGoals: { value: FitnessGoal; label: string }[] = [
  { value: "build-muscle", label: "Build Muscle" },
  { value: "lose-fat", label: "Lose Fat" },
  { value: "improve-endurance", label: "Improve Endurance" },
  { value: "general-fitness", label: "General Fitness" },
  { value: "athletic-performance", label: "Athletic Performance" },
];

const experienceLevels: {
  value: ExperienceLevel;
  label: string;
  description: string;
}[] = [
  {
    value: "beginner",
    label: "Beginner",
    description: "New to structured training. Learning the fundamentals.",
  },
  {
    value: "intermediate",
    label: "Intermediate",
    description: "Consistent training for 1-3 years. Solid foundation.",
  },
  {
    value: "advanced",
    label: "Advanced",
    description: "3+ years of dedicated training. Refined technique.",
  },
  {
    value: "elite",
    label: "Elite",
    description: "Competitive athlete or 5+ years of advanced training.",
  },
];

const workoutTypes: { value: WorkoutType; label: string }[] = [
  { value: "strength", label: "Strength" },
  { value: "cardio", label: "Cardio" },
  { value: "hiit", label: "HIIT" },
  { value: "yoga", label: "Yoga" },
  { value: "mobility", label: "Mobility" },
  { value: "sport-specific", label: "Sport-Specific" },
];

const sectionVariants = {
  enter: { opacity: 0, x: 30 },
  center: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
  exit: {
    opacity: 0,
    x: -30,
    transition: { duration: 0.3, ease: "easeIn" as const },
  },
};

export default function ProfileSetup({ onNext, onBack }: ProfileSetupProps) {
  const updateProfile = useAppStore((s) => s.updateProfile);

  const [section, setSection] = useState(0);
  const [name, setName] = useState("");
  const [selectedGoals, setSelectedGoals] = useState<FitnessGoal[]>([]);
  const [experienceLevel, setExperienceLevel] =
    useState<ExperienceLevel | null>(null);
  const [selectedWorkouts, setSelectedWorkouts] = useState<WorkoutType[]>([]);

  const toggleGoal = (goal: FitnessGoal) => {
    setSelectedGoals((prev) =>
      prev.includes(goal) ? prev.filter((g) => g !== goal) : [...prev, goal]
    );
  };

  const toggleWorkout = (type: WorkoutType) => {
    setSelectedWorkouts((prev) =>
      prev.includes(type) ? prev.filter((t) => t !== type) : [...prev, type]
    );
  };

  const canProceed = () => {
    switch (section) {
      case 0:
        return name.trim().length > 0;
      case 1:
        return selectedGoals.length > 0;
      case 2:
        return experienceLevel !== null;
      case 3:
        return selectedWorkouts.length > 0;
      default:
        return false;
    }
  };

  const handleContinue = () => {
    if (section < 3) {
      setSection((s) => s + 1);
    } else {
      updateProfile({
        name: name.trim(),
        fitnessGoals: selectedGoals,
        experienceLevel: experienceLevel!,
        preferredWorkouts: selectedWorkouts,
      });
      onNext();
    }
  };

  const whisper = useMemo(
    () =>
      whisperForStep("profile", {
        name,
        goals: selectedGoals,
        experience: experienceLevel,
        workouts: selectedWorkouts,
      }),
    [name, selectedGoals, experienceLevel, selectedWorkouts]
  );

  return (
    <div className="flex min-h-[100dvh] flex-col px-6 pb-8 pt-12">
      {/* Section indicator */}
      <div className="mb-2 flex items-center justify-center gap-2">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={cn(
              "h-1 rounded-full transition-all duration-300",
              i === section
                ? "w-8 bg-ember"
                : i < section
                  ? "w-4 bg-ember/50"
                  : "w-4 bg-border"
            )}
          />
        ))}
      </div>

      <div className="mb-5 mt-4">
        <AriaCompanion whisper={whisper} compact />
      </div>

      {/* Content area */}
      <div className="flex flex-1 flex-col">
        <AnimatePresence mode="wait">
          {section === 0 && (
            <motion.div
              key="name"
              variants={sectionVariants}
              initial="enter"
              animate="center"
              exit="exit"
              className="flex flex-1 flex-col pt-4"
            >
              <h2 className="mb-2 text-3xl font-bold text-text-primary">
                What should ARIA call you?
              </h2>
              <p className="mb-8 text-text-tertiary">
                Your intelligence layer learns your name first — everything else gets personal from here.
              </p>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Enter your name"
                autoFocus
                className={cn(
                  "w-full rounded-xl border border-border bg-surface px-5 py-4",
                  "text-lg text-text-primary placeholder:text-text-muted",
                  "outline-none transition-all duration-200",
                  "focus:border-ember focus:ring-1 focus:ring-ember/30"
                )}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && canProceed()) handleContinue();
                }}
              />
            </motion.div>
          )}

          {section === 1 && (
            <motion.div
              key="goals"
              variants={sectionVariants}
              initial="enter"
              animate="center"
              exit="exit"
              className="flex flex-1 flex-col pt-12"
            >
              <h2 className="mb-2 text-3xl font-bold text-text-primary">
                What are your fitness goals?
              </h2>
              <p className="mb-8 text-text-tertiary">
                Select all that apply. We&apos;ll tailor your training plan.
              </p>
              <div className="flex flex-wrap gap-3">
                {fitnessGoals.map((goal) => {
                  const selected = selectedGoals.includes(goal.value);
                  return (
                    <motion.button
                      key={goal.value}
                      onClick={() => toggleGoal(goal.value)}
                      className={cn(
                        "rounded-full border px-5 py-2.5 text-sm font-medium",
                        "transition-all duration-200",
                        selected
                          ? "border-ember bg-ember/15 text-ember"
                          : "border-border bg-surface text-text-secondary hover:border-border-light hover:text-text-primary"
                      )}
                      whileHover={{ scale: 1.03 }}
                      whileTap={{ scale: 0.97 }}
                    >
                      {goal.label}
                    </motion.button>
                  );
                })}
              </div>
            </motion.div>
          )}

          {section === 2 && (
            <motion.div
              key="experience"
              variants={sectionVariants}
              initial="enter"
              animate="center"
              exit="exit"
              className="flex flex-1 flex-col pt-12"
            >
              <h2 className="mb-2 text-3xl font-bold text-text-primary">
                Experience level?
              </h2>
              <p className="mb-8 text-text-tertiary">
                This helps us calibrate the right intensity for you.
              </p>
              <div className="flex flex-col gap-3">
                {experienceLevels.map((level) => {
                  const selected = experienceLevel === level.value;
                  return (
                    <motion.button
                      key={level.value}
                      onClick={() => setExperienceLevel(level.value)}
                      className={cn(
                        "flex flex-col items-start rounded-xl border p-4 text-left",
                        "transition-all duration-200",
                        selected
                          ? "border-ember bg-ember/10 shadow-[0_0_20px_rgba(255,77,0,0.1)]"
                          : "border-border bg-surface hover:border-border-light"
                      )}
                      whileHover={{ scale: 1.01 }}
                      whileTap={{ scale: 0.99 }}
                    >
                      <span
                        className={cn(
                          "text-base font-semibold",
                          selected ? "text-ember" : "text-text-primary"
                        )}
                      >
                        {level.label}
                      </span>
                      <span className="mt-1 text-sm text-text-tertiary">
                        {level.description}
                      </span>
                    </motion.button>
                  );
                })}
              </div>
            </motion.div>
          )}

          {section === 3 && (
            <motion.div
              key="workouts"
              variants={sectionVariants}
              initial="enter"
              animate="center"
              exit="exit"
              className="flex flex-1 flex-col pt-12"
            >
              <h2 className="mb-2 text-3xl font-bold text-text-primary">
                Preferred workout types?
              </h2>
              <p className="mb-8 text-text-tertiary">
                Pick the types of training you enjoy most.
              </p>
              <div className="flex flex-wrap gap-3">
                {workoutTypes.map((type) => {
                  const selected = selectedWorkouts.includes(type.value);
                  return (
                    <motion.button
                      key={type.value}
                      onClick={() => toggleWorkout(type.value)}
                      className={cn(
                        "rounded-full border px-5 py-2.5 text-sm font-medium",
                        "transition-all duration-200",
                        selected
                          ? "border-ember bg-ember/15 text-ember"
                          : "border-border bg-surface text-text-secondary hover:border-border-light hover:text-text-primary"
                      )}
                      whileHover={{ scale: 1.03 }}
                      whileTap={{ scale: 0.97 }}
                    >
                      {type.label}
                    </motion.button>
                  );
                })}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <div className="mt-8 flex gap-2">
        {(section > 0 || onBack) && (
          <button
            type="button"
            onClick={() => {
              if (section > 0) setSection((s) => s - 1);
              else onBack?.();
            }}
            className="rounded-xl border border-border px-5 py-4 text-sm font-semibold text-text-secondary"
          >
            Back
          </button>
        )}
      <motion.button
        onClick={handleContinue}
        disabled={!canProceed()}
        className={cn(
          "w-full flex-1 rounded-xl px-8 py-4 text-lg font-semibold text-white",
          "transition-all duration-300",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background",
          "disabled:cursor-not-allowed disabled:opacity-40"
        )}
        style={{
          background: canProceed()
            ? "linear-gradient(135deg, #FF4D00, #FF6B2B)"
            : "#2A2A2A",
        }}
        whileHover={canProceed() ? { scale: 1.02, boxShadow: "0 0 30px rgba(255,77,0,0.4)" } : {}}
        whileTap={canProceed() ? { scale: 0.98 } : {}}
      >
        Continue
      </motion.button>
      </div>
    </div>
  );
}
