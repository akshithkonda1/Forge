"use client";

import { useEffect, useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AuthProvider } from "react-oidc-context";
import { oidcConfig } from "@/lib/auth/oidc";
import { useAppStore } from "@/stores/useAppStore";

function PersistenceHydrator({ children }: { children: React.ReactNode }) {
  const hydratePersistence = useAppStore((s) => s.hydratePersistence);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    hydratePersistence();
    setReady(true);
  }, [hydratePersistence]);

  if (!ready) {
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-background">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-ember border-t-transparent" />
      </div>
    );
  }

  return <>{children}</>;
}

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: false },
        },
      }),
  );

  return (
    <AuthProvider {...oidcConfig}>
      <QueryClientProvider client={queryClient}>
        <PersistenceHydrator>{children}</PersistenceHydrator>
      </QueryClientProvider>
    </AuthProvider>
  );
}