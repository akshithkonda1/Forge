"use client";

import { useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import {
  clearOnboardingDraft,
  readOnboardingDraft,
} from "@/lib/device-connect";
import type { UserProfile } from "@/types";
import WelcomeScreen from "@/components/onboarding/welcome-screen";
import ProfileSetup from "@/components/onboarding/profile-setup";
import DeviceConnection from "@/components/onboarding/device-connection";
import CoachingStyleScreen from "@/components/onboarding/coaching-style";

const TOTAL_STEPS = 4;

const pageVariants = {
  enter: { opacity: 0, x: 60 },
  center: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
  exit: {
    opacity: 0,
    x: -60,
    transition: { duration: 0.3, ease: "easeIn" as const },
  },
};

export default function OnboardingPage() {
  const router = useRouter();
  const isOnboarded = useAppStore((s) => s.isOnboarded);
  const onboardingStep = useAppStore((s) => s.onboardingStep);
  const setOnboardingStep = useAppStore((s) => s.setOnboardingStep);
  const updateProfile = useAppStore((s) => s.updateProfile);
  const refreshProfileFromAPI = useAppStore((s) => s.refreshProfileFromAPI);

  useEffect(() => {
    if (isOnboarded) {
      router.replace("/");
    }
  }, [isOnboarded, router]);

  useEffect(() => {
    const draft = readOnboardingDraft();
    if (!draft) return;

    setOnboardingStep(draft.step);
    updateProfile(draft.profile as Partial<UserProfile>);
    clearOnboardingDraft();
    void refreshProfileFromAPI();
  }, [refreshProfileFromAPI, setOnboardingStep, updateProfile]);

  const handleNext = useCallback(() => {
    setOnboardingStep(onboardingStep + 1);
  }, [onboardingStep, setOnboardingStep]);

  const handleComplete = useCallback(() => {
    router.replace("/");
  }, [router]);

  if (isOnboarded) {
    return null;
  }

  return (
    <div className="relative min-h-[100dvh] bg-background">
      {/* Progress dots — visible on steps 1-3 (not on welcome) */}
      {onboardingStep > 0 && (
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="fixed left-0 right-0 top-0 z-50 flex items-center justify-center gap-2 pb-2 pt-4"
          style={{
            background:
              "linear-gradient(180deg, #0A0A0A 60%, transparent 100%)",
          }}
        >
          {Array.from({ length: TOTAL_STEPS }).map((_, i) => (
            <div
              key={i}
              className={cn(
                "h-1.5 rounded-full transition-all duration-500",
                i === onboardingStep
                  ? "w-8 bg-ember"
                  : i < onboardingStep
                    ? "w-3 bg-ember/40"
                    : "w-3 bg-border"
              )}
            />
          ))}
        </motion.div>
      )}

      {/* Screen transitions */}
      <AnimatePresence mode="wait">
        {onboardingStep === 0 && (
          <motion.div
            key="welcome"
            variants={pageVariants}
            initial="enter"
            animate="center"
            exit="exit"
          >
            <WelcomeScreen onNext={handleNext} />
          </motion.div>
        )}

        {onboardingStep === 1 && (
          <motion.div
            key="profile"
            variants={pageVariants}
            initial="enter"
            animate="center"
            exit="exit"
          >
            <ProfileSetup onNext={handleNext} />
          </motion.div>
        )}

        {onboardingStep === 2 && (
          <motion.div
            key="devices"
            variants={pageVariants}
            initial="enter"
            animate="center"
            exit="exit"
          >
            <DeviceConnection onNext={handleNext} />
          </motion.div>
        )}

        {onboardingStep === 3 && (
          <motion.div
            key="coaching"
            variants={pageVariants}
            initial="enter"
            animate="center"
            exit="exit"
          >
            <CoachingStyleScreen onComplete={handleComplete} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
