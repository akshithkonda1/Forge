import { isAuthConfigured } from "@/lib/auth-config";
import {
  refreshSession,
  shouldRefreshToken,
  type CognitoAuthTokens,
} from "@/lib/cognito-auth";
import { forgePersistence } from "@/lib/persistence";

type AuthListener = () => void;

let tokens: CognitoAuthTokens | null = null;
const listeners = new Set<AuthListener>();

function loadTokensFromPersistence(): CognitoAuthTokens | null {
  const stored = forgePersistence.getAuthTokens();
  if (!stored.idToken || !stored.accessToken) {
    return null;
  }
  return {
    idToken: stored.idToken,
    accessToken: stored.accessToken,
    refreshToken: stored.refreshToken ?? "",
  };
}

function notifyListeners(): void {
  for (const listener of listeners) {
    listener();
  }
}

export function initAuthSession(): void {
  tokens = loadTokensFromPersistence();
}

export function subscribeAuthSession(listener: AuthListener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getAuthTokens(): CognitoAuthTokens | null {
  return tokens;
}

export function isAuthenticated(): boolean {
  if (!isAuthConfigured()) return true;
  return tokens?.idToken != null;
}

export function requiresSignIn(): boolean {
  return isAuthConfigured() && !isAuthenticated();
}

export function getAuthorizationHeader(): string | undefined {
  if (!isAuthConfigured() || !tokens?.idToken) return undefined;
  return `Bearer ${tokens.idToken}`;
}

export function setAuthTokens(next: CognitoAuthTokens | null): void {
  tokens = next;
  if (next) {
    forgePersistence.setAuthTokens({
      idToken: next.idToken,
      accessToken: next.accessToken,
      refreshToken: next.refreshToken,
    });
  } else {
    forgePersistence.clearAuthTokens();
  }
  notifyListeners();
}

export function clearAuthSession(): void {
  setAuthTokens(null);
}

export async function refreshSessionIfNeeded(force = false): Promise<boolean> {
  if (!isAuthConfigured()) return true;
  if (!tokens?.refreshToken) {
    if (tokens?.idToken) {
      clearAuthSession();
    }
    return false;
  }

  if (!force && tokens.idToken && !shouldRefreshToken(tokens.idToken)) {
    return true;
  }

  try {
    const refreshed = await refreshSession(tokens.refreshToken);
    setAuthTokens(refreshed);
    return true;
  } catch {
    clearAuthSession();
    return false;
  }
}