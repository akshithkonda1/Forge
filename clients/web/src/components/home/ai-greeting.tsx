"use client";

import { useMemo } from "react";
import { motion } from "framer-motion";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import { getReadinessLabel } from "@/lib/utils";

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
  readiness: { overall: number; sleepQuality: number },
  metrics: { hrv: number; deepSleep: number },
  workoutName: string | undefined,
): string {
  const hour = new Date().getHours();
  const timeGreeting = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening";
  const displayName = name.trim() || "there";

  const deepSleepFormatted = formatDeepSleep(metrics.deepSleep);
  const readinessLabel = getReadinessLabel(readiness.overall).toLowerCase();

  const parts: string[] = [`${timeGreeting}, ${displayName}.`];

  if (readiness.sleepQuality >= 80) {
    parts.push(`Your deep sleep was solid last night — ${deepSleepFormatted}.`);
  } else if (readiness.sleepQuality >= 60) {
    parts.push(`Deep sleep came in at ${deepSleepFormatted} — decent, but room to improve.`);
  } else if (metrics.deepSleep > 0) {
    parts.push(`Only ${deepSleepFormatted} of deep sleep last night. Let's keep that in mind.`);
  }

  if (metrics.hrv >= 50) {
    parts.push(`HRV is looking strong at ${metrics.hrv}ms.`);
  } else if (metrics.hrv >= 35) {
    parts.push(`HRV is at ${metrics.hrv}ms — moderate range.`);
  } else if (metrics.hrv > 0) {
    parts.push(`HRV is low at ${metrics.hrv}ms — recovery might be lagging.`);
  }

  if (readiness.overall >= 80 && workoutName) {
    parts.push(`You're ${readinessLabel} for a heavy session today. Ready to hit ${workoutName}?`);
  } else if (readiness.overall >= 60 && workoutName) {
    parts.push(`You're in ${readinessLabel} shape. I've adjusted ${workoutName} to match your recovery.`);
  } else if (workoutName) {
    parts.push(`Recovery is lower today. I'd suggest going lighter on ${workoutName} or swapping for mobility.`);
  } else if (readiness.overall > 0) {
    parts.push("Today's a good day to rest and recover.");
  }

  return parts.join(" ");
}

export function AiGreeting() {
  const userProfile = useAppStore((s) => s.userProfile);
  const readiness = useAppStore((s) => s.readiness);
  const dailyMetrics = useAppStore((s) => s.dailyMetrics);
  const todayWorkout = useAppStore((s) => s.todayWorkout);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const primaryInsight = useAppStore((s) => s.primaryInsight);

  const greeting = useMemo(() => {
    const insight = primaryInsight();
    if (insight) {
      return `${insight.title}. ${insight.observation} ${insight.recommendation}`;
    }
    return buildGreeting(
      userProfile.name,
      readiness,
      dailyMetrics,
      todayWorkout?.name,
    );
  }, [userProfile.name, readiness, dailyMetrics, todayWorkout?.name, primaryInsight]);

  const containerVariants = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: { staggerChildren: 0.03, delayChildren: 0.2 },
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
      className={cn("rounded-2xl bg-surface border-l-2 border-l-ember", "p-4")}
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
    >
      <div className="flex items-start gap-3">
        <motion.div
          className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full bg-ember"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", stiffness: 260, damping: 20, delay: 0.1 }}
        >
          <span className="text-sm font-bold text-white">F</span>
        </motion.div>

        <div className="flex-1 min-w-0">
          <motion.p
            className="text-xs font-medium text-ember mb-1.5"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.1 }}
          >
            Forge AI Trainer
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

          <motion.button
            onClick={() => setActiveTab("chat")}
            className={cn(
              "mt-3 inline-flex items-center gap-1.5",
              "text-xs font-medium text-ember",
              "hover:text-ember-light transition-colors",
            )}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.2 }}
            whileHover={{ x: 2 }}
            whileTap={{ scale: 0.97 }}
          >
            <MessageCircle size={14} />
            Chat with Forge
          </motion.button>
        </div>
      </div>
    </motion.div>
  );
}