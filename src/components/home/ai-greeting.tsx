"use client";

import { useMemo } from "react";
import { motion } from "framer-motion";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import { getReadinessLabel } from "@/lib/utils";
import { AriaOrb } from "@/components/onboarding/aria-companion";

function formatDeepSleep(minutes: number): string {
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;
  if (hrs > 0) {
    return `${hrs}hr ${mins}min`;
  }
  return `${mins}min`;
}

function buildGreeting(
  name: string,
  readiness: { overall: number; sleepQuality: number; recoveryScore: number; stressLevel: number; energyBank: number },
  metrics: { hrv: number; deepSleep: number; restingHR: number; steps: number; activeCalories: number; totalSleep: number },
  workoutName: string | undefined
): string {
  const hour = new Date().getHours();
  const timeGreeting = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening";

  const deepSleepFormatted = formatDeepSleep(metrics.deepSleep);
  const readinessLabel = getReadinessLabel(readiness.overall).toLowerCase();

  const parts: string[] = [];

  parts.push(`${timeGreeting} ${name}.`);

  // Sleep commentary
  if (readiness.sleepQuality >= 80) {
    parts.push(`Your deep sleep was solid last night \u2014 ${deepSleepFormatted}.`);
  } else if (readiness.sleepQuality >= 60) {
    parts.push(`Deep sleep came in at ${deepSleepFormatted} \u2014 decent, but room to improve.`);
  } else {
    parts.push(`Only ${deepSleepFormatted} of deep sleep last night. Let\u2019s keep that in mind.`);
  }

  // HRV commentary
  if (metrics.hrv >= 50) {
    parts.push(`HRV is looking strong at ${metrics.hrv}ms.`);
  } else if (metrics.hrv >= 35) {
    parts.push(`HRV is at ${metrics.hrv}ms \u2014 moderate range.`);
  } else {
    parts.push(`HRV is low at ${metrics.hrv}ms \u2014 recovery might be lagging.`);
  }

  // Readiness + workout recommendation
  if (readiness.overall >= 80 && workoutName) {
    parts.push(`You\u2019re ${readinessLabel} for a heavy session today. Ready to hit ${workoutName}?`);
  } else if (readiness.overall >= 60 && workoutName) {
    parts.push(`You\u2019re in ${readinessLabel} shape. I\u2019ve adjusted ${workoutName} to match your recovery.`);
  } else if (workoutName) {
    parts.push(`Recovery is lower today. I\u2019d suggest going lighter on ${workoutName} or swapping for mobility.`);
  } else {
    parts.push(`Today\u2019s a good day to rest and recover.`);
  }

  return parts.join(" ");
}

export function AiGreeting() {
  const { userProfile, readiness, dailyMetrics, todayWorkout, setActiveTab } =
    useAppStore();

  const greeting = useMemo(
    () =>
      buildGreeting(
        userProfile.name,
        readiness,
        dailyMetrics,
        todayWorkout?.name
      ),
    [userProfile.name, readiness, dailyMetrics, todayWorkout?.name]
  );

  const containerVariants = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: {
        staggerChildren: 0.03,
        delayChildren: 0.2,
      },
    },
  };

  const wordVariants = {
    hidden: { opacity: 0, y: 4, filter: "blur(4px)" },
    visible: {
      opacity: 1,
      y: 0,
      filter: "blur(0px)",
      transition: { duration: 0.3, ease: "easeOut" as const },
    },
  };

  const words = greeting.split(" ");

  return (
    <motion.div
      className={cn(
        "rounded-2xl bg-surface border-l-2 border-l-ember",
        "p-4"
      )}
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
    >
      <div className="flex items-start gap-3">
        <motion.div
          className="flex-shrink-0"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", stiffness: 260, damping: 20, delay: 0.1 }}
        >
          <AriaOrb mood="focused" size={36} />
        </motion.div>

        {/* Greeting text */}
        <div className="flex-1 min-w-0">
          <motion.p
            className="text-xs font-medium text-ember mb-1.5"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.1 }}
          >
            ARIA
          </motion.p>

          <motion.p
            className="text-sm leading-relaxed text-text-primary"
            variants={containerVariants}
            initial="hidden"
            animate="visible"
          >
            {words.map((word, i) => (
              <motion.span
                key={`${word}-${i}`}
                variants={wordVariants}
                className="inline-block mr-[0.25em]"
              >
                {word}
              </motion.span>
            ))}
          </motion.p>

          {/* Chat link */}
          <motion.button
            onClick={() => setActiveTab("chat")}
            className={cn(
              "mt-3 inline-flex items-center gap-1.5",
              "text-xs font-medium text-ember",
              "hover:text-ember-light transition-colors"
            )}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.2 }}
            whileHover={{ x: 2 }}
            whileTap={{ scale: 0.97 }}
          >
            <MessageCircle size={14} />
            Talk with ARIA
          </motion.button>
        </div>
      </div>
    </motion.div>
  );
}
