"use client";

import { useAuth } from "react-oidc-context";
import { env } from "@/lib/env";
import { cognitoLogout } from "@/lib/auth/oidc";

export interface ForgeAuth {
  /** False while the auth library is still resolving the session. */
  isReady: boolean;
  isAuthenticated: boolean;
  /** Bearer token for API calls, or null in auth-disabled dev mode. */
  idToken: string | null;
  email: string | null;
  signIn: () => void;
  signOut: () => void;
}

/**
 * Single source of truth for auth state across the app.
 *
 * `useAuth()` is always called (the AuthProvider is always mounted), keeping
 * hook order stable. In auth-disabled mode we ignore the OIDC result and report
 * an authenticated dev session with no token — the local backend resolves
 * identity from FORGE_TEST_USER_ID instead.
 */
export function useForgeAuth(): ForgeAuth {
  const auth = useAuth();

  if (env.authDisabled) {
    return {
      isReady: true,
      isAuthenticated: true,
      idToken: null,
      email: "dev@forge.local",
      signIn: () => {},
      signOut: () => {},
    };
  }

  return {
    isReady: !auth.isLoading,
    isAuthenticated: auth.isAuthenticated,
    idToken: auth.user?.id_token ?? null,
    email: (auth.user?.profile?.email as string | undefined) ?? null,
    signIn: () => {
      void auth.signinRedirect();
    },
    signOut: cognitoLogout,
  };
}
