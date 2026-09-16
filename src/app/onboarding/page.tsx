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
    // Never leave the gate hanging if persist is slow/odd in a tab.
    const failsafe = window.setTimeout(finish, 250);
    return () => {
      unsub();
      window.clearTimeout(failsafe);
    };
  }, [setHasHydrated]);

  useEffect(() => {
    if (hasHydrated && isOnboarded) {
      router.replace("/");
    }
  }, [hasHydrated, isOnboarded, router]);

  const handleNext = useCallback(() => {
    const step = useAppStore.getState().onboardingStep;
    // #region agent log
    {const __dbg={location:'onboarding/page.tsx:handleNext',message:'handleNext entry',data:{step,hasHydrated:useAppStore.getState().hasHydrated,isOnboarded:useAppStore.getState().isOnboarded},timestamp:Date.now(),hypothesisId:'B'};fetch('http://127.0.0.1:7252/ingest/4f8a2c91-onboarding-step',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'onboarding-step'},body:JSON.stringify(__dbg)}).catch(()=>{});fetch('/api/agent-debug',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(__dbg)}).catch(()=>{});}
    // #endregion
    setOnboardingStep(step + 1);
    // #region agent log
    queueMicrotask(() => {
      const after = useAppStore.getState();
      {const __dbg={location:'onboarding/page.tsx:handleNext:after',message:'state after setOnboardingStep',data:{onboardingStep:after.onboardingStep,hasHydrated:after.hasHydrated,isOnboarded:after.isOnboarded},timestamp:Date.now(),hypothesisId:'B'};fetch('http://127.0.0.1:7252/ingest/4f8a2c91-onboarding-step',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'onboarding-step'},body:JSON.stringify(__dbg)}).catch(()=>{});fetch('/api/agent-debug',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(__dbg)}).catch(()=>{});}
    });
    // #endregion
  }, [setOnboardingStep]);

  const handleBack = useCallback(() => {
    const step = useAppStore.getState().onboardingStep;
    setOnboardingStep(Math.max(0, step - 1));
  }, [setOnboardingStep]);

  const handleComplete = useCallback(() => {
    router.replace("/");
  }, [router]);

  // #region agent log
  useEffect(() => {
    {const __dbg={location:'onboarding/page.tsx:renderGate',message:'onboarding gate/render state',data:{onboardingStep,hasHydrated,isOnboarded},timestamp:Date.now(),hypothesisId:'D'};fetch('http://127.0.0.1:7252/ingest/4f8a2c91-onboarding-step',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'onboarding-step'},body:JSON.stringify(__dbg)}).catch(()=>{});fetch('/api/agent-debug',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(__dbg)}).catch(()=>{});}
  }, [onboardingStep, hasHydrated, isOnboarded]);
  // #endregion

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
