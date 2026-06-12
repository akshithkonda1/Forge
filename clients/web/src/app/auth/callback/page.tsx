"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "react-oidc-context";

// Cognito Hosted UI redirects here with ?code&state. react-oidc-context
// processes the exchange automatically; we just wait and route onward.
export default function AuthCallbackPage() {
  const auth = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (auth.isLoading) return;
    if (auth.isAuthenticated) router.replace("/");
  }, [auth.isLoading, auth.isAuthenticated, router]);

  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-background text-text-secondary">
      {auth.error ? (
        <div className="flex flex-col items-center gap-3 text-center">
          <p className="text-sm text-red-400">Sign-in failed: {auth.error.message}</p>
          <button
            onClick={() => auth.signinRedirect()}
            className="rounded-full bg-ember px-4 py-2 text-sm text-white"
          >
            Try again
          </button>
        </div>
      ) : (
        <p className="text-sm">Signing you in…</p>
      )}
    </div>
  );
}
