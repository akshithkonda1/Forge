"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { isAuthConfigured } from "@/lib/auth-config";
import {
  confirmSignUp as cognitoConfirmSignUp,
  signIn as cognitoSignIn,
  signUp as cognitoSignUp,
  CognitoAuthError,
} from "@/lib/cognito-auth";
import {
  clearAuthSession,
  initAuthSession,
  isAuthenticated as sessionIsAuthenticated,
  refreshSessionIfNeeded,
  setAuthTokens,
  subscribeAuthSession,
} from "@/lib/auth-session";

interface AuthContextValue {
  ready: boolean;
  isAuthenticated: boolean;
  requiresSignIn: boolean;
  lastError: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  confirmSignUp: (email: string, code: string) => Promise<void>;
  signOut: () => void;
  refreshSessionIfNeeded: (force?: boolean) => Promise<boolean>;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);

  useEffect(() => {
    initAuthSession();
    setAuthenticated(sessionIsAuthenticated());
    setReady(true);

    return subscribeAuthSession(() => {
      setAuthenticated(sessionIsAuthenticated());
    });
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    const tokens = await cognitoSignIn(email, password);
    setAuthTokens(tokens);
    setLastError(null);
  }, []);

  const signUp = useCallback(async (email: string, password: string) => {
    await cognitoSignUp(email, password);
    setLastError(null);
  }, []);

  const confirmSignUp = useCallback(async (email: string, code: string) => {
    await cognitoConfirmSignUp(email, code);
    setLastError(null);
  }, []);

  const signOut = useCallback(() => {
    clearAuthSession();
    setLastError(null);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      ready,
      isAuthenticated: authenticated,
      requiresSignIn: isAuthConfigured() && !authenticated,
      lastError,
      signIn: async (email, password) => {
        try {
          await signIn(email, password);
        } catch (error) {
          const message =
            error instanceof CognitoAuthError
              ? error.message
              : error instanceof Error
                ? error.message
                : "Sign in failed";
          setLastError(message);
          throw error;
        }
      },
      signUp: async (email, password) => {
        try {
          await signUp(email, password);
        } catch (error) {
          const message =
            error instanceof CognitoAuthError
              ? error.message
              : error instanceof Error
                ? error.message
                : "Sign up failed";
          setLastError(message);
          throw error;
        }
      },
      confirmSignUp: async (email, code) => {
        try {
          await confirmSignUp(email, code);
        } catch (error) {
          const message =
            error instanceof CognitoAuthError
              ? error.message
              : error instanceof Error
                ? error.message
                : "Confirmation failed";
          setLastError(message);
          throw error;
        }
      },
      signOut,
      refreshSessionIfNeeded,
      clearError: () => setLastError(null),
    }),
    [ready, authenticated, lastError, signIn, signUp, confirmSignUp, signOut],
  );

  if (!ready && isAuthConfigured()) {
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-background">
        <div
          className="h-8 w-8 animate-spin rounded-full border-2 border-ember border-t-transparent"
          role="status"
          aria-label="Loading auth"
        />
      </div>
    );
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within AuthProvider");
  }
  return context;
}