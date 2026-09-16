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
import { AriaMark } from "@/components/brand/aria-mark";
import { ForgeBrandMark, PremiumAtmosphere } from "@/components/brand/premium-atmosphere";

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
    const step = useAppStore.getState().onboardingStep;
    setOnboardingStep(step + 1);
  }, [setOnboardingStep]);

  const handleBack = useCallback(() => {
    const step = useAppStore.getState().onboardingStep;
    setOnboardingStep(Math.max(0, step - 1));
  }, [setOnboardingStep]);

  const handleComplete = useCallback(() => {
    router.replace("/");
  }, [router]);

  if (!hasHydrated) {
    return (
      <div className="relative mx-auto flex min-h-[100dvh] max-w-lg flex-col items-center justify-center bg-background">
        <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={0.55} />
        <div className="relative z-10 flex flex-col items-center gap-3">
          <ForgeBrandMark size={22} />
          <p className="text-[12px] font-medium uppercase tracking-[0.28em] text-text-tertiary">
            Loading…
          </p>
        </div>
      </div>
    );
  }

  if (isOnboarded) {
    return null;
  }

  return (
    <div className="relative mx-auto min-h-[100dvh] max-w-lg bg-background pb-[env(safe-area-inset-bottom)] pt-[env(safe-area-inset-top)]">
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
          <AriaMark size={36} speaking={false} className="absolute right-4 top-2.5" />
          {Array.from({ length: FLOW_STEPS }).map((_, i) => {
            const step = i + 1;
            return (
              <div
                key={i}
                className={cn(
                  "h-1.5 rounded-full transition-all duration-200",
                  step === onboardingStep
                    ? "premium-dot-active w-8 bg-[#F7F4F0]"
                    : step < onboardingStep
                      ? "w-3 bg-[#F7F4F0]/40"
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
