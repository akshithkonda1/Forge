"use client";

import { useAuth } from "@/components/providers/auth-provider";
import { SignInForm } from "@/components/auth/sign-in-form";
import { useAppStore } from "@/stores/useAppStore";

export function AuthGate() {
  const { requiresSignIn } = useAuth();
  const saveProfileToAPI = useAppStore((s) => s.saveProfileToAPI);
  const loadDashboardFromAPI = useAppStore((s) => s.loadDashboardFromAPI);
  const userProfile = useAppStore((s) => s.userProfile);

  if (!requiresSignIn) {
    return null;
  }

  const handleSuccess = () => {
    void (async () => {
      try {
        await saveProfileToAPI(userProfile);
      } catch {
        // Profile may already exist; continue to dashboard load.
      }
      await loadDashboardFromAPI();
    })();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/95 px-4 backdrop-blur-sm">
      <SignInForm onSuccess={handleSuccess} />
    </div>
  );
}