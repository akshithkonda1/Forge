"use client";

import { AriaIntro } from "@/components/brand/aria-intro";
import { ARIA_INTRO } from "@/lib/aria-intro";

interface WelcomeScreenProps {
  onNext: () => void;
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  return <AriaIntro ctaLabel={ARIA_INTRO.continueCta} onContinue={onNext} />;
}
