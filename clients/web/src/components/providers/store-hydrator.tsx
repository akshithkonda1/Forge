"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/providers/auth-provider";
import { useAppStore } from "@/stores/useAppStore";

function StoreHydratorInner({ children }: { children: React.ReactNode }) {
  const hydrate = useAppStore((s) => s.hydrate);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    hydrate();
    setReady(true);
  }, [hydrate]);

  if (!ready) {
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-background">
        <div
          className="h-8 w-8 animate-spin rounded-full border-2 border-ember border-t-transparent"
          role="status"
          aria-label="Loading"
        />
      </div>
    );
  }

  return <>{children}</>;
}

export function StoreHydrator({ children }: { children: React.ReactNode }) {
  return (
    <AuthProvider>
      <StoreHydratorInner>{children}</StoreHydratorInner>
    </AuthProvider>
  );
}