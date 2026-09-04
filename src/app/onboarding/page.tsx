"use client";

import { useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import { ChevronLeft } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import WelcomeScreen from "@/components/onboarding/welcome-screen";
import ProfileSetup from "@/components/onboarding/profile-setup";
import DeviceConnection from "@/components/onboarding/device-connection";
import CoachingStyleScreen from "@/components/onboarding/coaching-style";

const FLOW_STEPS = 3;

export default function OnboardingPage() {
  const router = useRouter();
  const onboardingStep = useAppStore((s) => s.onboardingStep);
  const setOnboardingStep = useAppStore((s) => s.setOnboardingStep);
  const isOnboarded = useAppStore((s) => s.isOnboarded);
  const hasHydrated = useAppStore((s) => s.hasHydrated);
  const setHasHydrated = useAppStore((s) => s.setHasHydrated);

  useEffect(() => {
    const finish = () => setHasHydrated(true);
    const unsub = useAppStore.persist.onFinishHydration(finish);
    if (useAppStore.persist.hasHydrated()) finish();
    return unsub;
  }, [setHasHydrated]);

  useEffect(() => {
    if (hasHydrated && isOnboarded) {
      router.replace("/");
    }
  }, [hasHydrated, isOnboarded, router]);

  const handleNext = useCallback(() => {
    setOnboardingStep(onboardingStep + 1);
  }, [onboardingStep, setOnboardingStep]);

  const handleBack = useCallback(() => {
    setOnboardingStep(onboardingStep - 1);
  }, [onboardingStep, setOnboardingStep]);

  const handleComplete = useCallback(() => {
    router.replace("/");
  }, [router]);

  return (
    <div className="relative mx-auto min-h-[100dvh] max-w-lg bg-background">
      {onboardingStep > 0 && (
        <div
          className="fixed left-0 right-0 top-0 z-50 mx-auto flex max-w-lg items-center justify-center gap-2 pb-2 pt-4"
          style={{
            background: "linear-gradient(180deg, #0A0A0A 60%, transparent 100%)",
          }}
        >
          <button
            type="button"
            onClick={handleBack}
            aria-label="Back"
            className="absolute left-4 top-3 flex h-9 w-9 items-center justify-center rounded-full border border-border bg-surface/80 text-text-secondary"
          >
            <ChevronLeft size={18} />
          </button>
          {Array.from({ length: FLOW_STEPS }).map((_, i) => {
            const step = i + 1;
            return (
              <div
                key={i}
                className={cn(
                  "h-1.5 rounded-full transition-all duration-200",
                  step === onboardingStep
                    ? "w-8 bg-ember"
                    : step < onboardingStep
                      ? "w-3 bg-ember/40"
                      : "w-3 bg-border"
                )}
              />
            );
          })}
        </div>
      )}

      {onboardingStep === 0 && <WelcomeScreen onNext={handleNext} />}
      {onboardingStep === 1 && <ProfileSetup onNext={handleNext} onBack={handleBack} />}
      {onboardingStep === 2 && <DeviceConnection onNext={handleNext} />}
      {onboardingStep === 3 && <CoachingStyleScreen onComplete={handleComplete} />}
    </div>
  );
}
