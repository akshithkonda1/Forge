"use client";

import { useState } from "react";
import { useAuth } from "@/components/providers/auth-provider";
import { cn } from "@/lib/utils";

type AuthMode = "sign-in" | "sign-up" | "confirm";

interface SignInFormProps {
  onSuccess?: () => void;
  className?: string;
}

export function SignInForm({ onSuccess, className }: SignInFormProps) {
  const auth = useAuth();
  const [mode, setMode] = useState<AuthMode>("sign-in");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmationCode, setConfirmationCode] = useState("");
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  const submit = async () => {
    setIsLoading(true);
    setStatusMessage(null);
    auth.clearError();

    try {
      if (mode === "sign-in") {
        await auth.signIn(email, password);
        setStatusMessage("Signed in successfully.");
        onSuccess?.();
      } else if (mode === "sign-up") {
        await auth.signUp(email, password);
        setStatusMessage("Check your email for a confirmation code.");
        setMode("confirm");
      } else {
        await auth.confirmSignUp(email, confirmationCode);
        setStatusMessage("Email confirmed. You can sign in now.");
        setMode("sign-in");
      }
    } catch {
      // Error surfaced via auth.lastError
    } finally {
      setIsLoading(false);
    }
  };

  const primaryLabel =
    mode === "sign-in" ? "Sign In" : mode === "sign-up" ? "Create Account" : "Confirm";

  return (
    <div
      className={cn(
        "w-full max-w-md rounded-2xl border border-border/70 bg-surface/95 p-6 shadow-xl",
        className,
      )}
    >
      <h2 className="text-xl font-bold text-text-primary">Forge Account</h2>
      <p className="mt-2 text-sm text-text-secondary">
        Sign in to sync workouts, readiness, and ARIA history to your account.
      </p>

      <div className="mt-5 flex gap-2">
        {(["sign-in", "sign-up", "confirm"] as AuthMode[]).map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setMode(item)}
            className={cn(
              "rounded-full px-3 py-1.5 text-xs font-semibold transition-colors",
              mode === item
                ? "bg-ember text-white"
                : "bg-background text-text-secondary hover:text-text-primary",
            )}
          >
            {item === "sign-in" ? "Sign In" : item === "sign-up" ? "Sign Up" : "Confirm"}
          </button>
        ))}
      </div>

      <div className="mt-4 space-y-3">
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="Email"
          autoComplete="email"
          className="w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm text-text-primary outline-none focus:border-ember"
        />
        <input
          type="password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="Password"
          autoComplete={mode === "sign-up" ? "new-password" : "current-password"}
          className="w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm text-text-primary outline-none focus:border-ember"
        />
        {mode === "confirm" && (
          <input
            type="text"
            value={confirmationCode}
            onChange={(event) => setConfirmationCode(event.target.value)}
            placeholder="Confirmation code"
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm text-text-primary outline-none focus:border-ember"
          />
        )}
      </div>

      {statusMessage && (
        <p className="mt-3 text-xs text-text-secondary">{statusMessage}</p>
      )}
      {auth.lastError && (
        <p className="mt-3 text-xs text-danger">{auth.lastError}</p>
      )}

      <button
        type="button"
        disabled={isLoading || !email || !password || (mode === "confirm" && !confirmationCode)}
        onClick={() => void submit()}
        className="mt-5 w-full rounded-xl bg-ember px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
      >
        {isLoading ? "Working…" : primaryLabel}
      </button>
    </div>
  );
}