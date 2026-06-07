import {
  cognitoClientId,
  cognitoEndpoint,
  isAuthConfigured,
} from "@/lib/auth-config";

export const REFRESH_LEAD_TIME_MS = 5 * 60 * 1000;

export class CognitoAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CognitoAuthError";
  }
}

export interface CognitoAuthTokens {
  idToken: string;
  accessToken: string;
  refreshToken: string;
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;

  let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const remainder = payload.length % 4;
  if (remainder > 0) {
    payload += "=".repeat(4 - remainder);
  }

  try {
    const decoded = atob(payload);
    return JSON.parse(decoded) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function tokenExpirationMs(token: string): number | null {
  const payload = decodeJwtPayload(token);
  const exp = payload?.exp;
  return typeof exp === "number" ? exp * 1000 : null;
}

export function shouldRefreshToken(
  idToken: string,
  now = Date.now(),
  leadTimeMs = REFRESH_LEAD_TIME_MS,
): boolean {
  const expiration = tokenExpirationMs(idToken);
  if (expiration == null) return true;
  return expiration - now <= leadTimeMs;
}

export function refreshAuthPayload(
  clientId: string,
  refreshToken: string,
): Record<string, unknown> {
  return {
    AuthFlow: "REFRESH_TOKEN_AUTH",
    ClientId: clientId,
    AuthParameters: {
      REFRESH_TOKEN: refreshToken,
    },
  };
}

async function invokeCognito(
  target: string,
  payload: Record<string, unknown>,
  fetchImpl: typeof fetch = fetch,
): Promise<Record<string, unknown>> {
  const response = await fetchImpl(cognitoEndpoint(), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": target,
    },
    body: JSON.stringify(payload),
  });

  const body = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (response.ok) {
    return body;
  }

  const message =
    (typeof body.message === "string" && body.message) ||
    `Cognito request failed (${response.status})`;
  throw new CognitoAuthError(message);
}

function parseAuthResult(body: Record<string, unknown>): CognitoAuthTokens {
  const result = body.AuthenticationResult as Record<string, unknown> | undefined;
  const idToken = typeof result?.IdToken === "string" ? result.IdToken : "";
  const accessToken = typeof result?.AccessToken === "string" ? result.AccessToken : "";
  const refreshToken = typeof result?.RefreshToken === "string" ? result.RefreshToken : "";

  if (!idToken || !accessToken) {
    throw new CognitoAuthError("Unexpected response from Cognito.");
  }

  return {
    idToken,
    accessToken,
    refreshToken,
  };
}

export async function signUp(
  email: string,
  password: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  ensureConfigured();
  await invokeCognito(
    "AWSCognitoIdentityProviderService.SignUp",
    {
      ClientId: cognitoClientId(),
      Username: email,
      Password: password,
      UserAttributes: [{ Name: "email", Value: email }],
    },
    fetchImpl,
  );
}

export async function confirmSignUp(
  email: string,
  code: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  ensureConfigured();
  await invokeCognito(
    "AWSCognitoIdentityProviderService.ConfirmSignUp",
    {
      ClientId: cognitoClientId(),
      Username: email,
      ConfirmationCode: code,
    },
    fetchImpl,
  );
}

export async function signIn(
  email: string,
  password: string,
  fetchImpl: typeof fetch = fetch,
): Promise<CognitoAuthTokens> {
  ensureConfigured();
  const body = await invokeCognito(
    "AWSCognitoIdentityProviderService.InitiateAuth",
    {
      AuthFlow: "USER_PASSWORD_AUTH",
      ClientId: cognitoClientId(),
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password,
      },
    },
    fetchImpl,
  );
  return parseAuthResult(body);
}

export async function refreshSession(
  refreshToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<CognitoAuthTokens> {
  ensureConfigured();
  const body = await invokeCognito(
    "AWSCognitoIdentityProviderService.InitiateAuth",
    refreshAuthPayload(cognitoClientId(), refreshToken),
    fetchImpl,
  );
  const tokens = parseAuthResult(body);
  return {
    ...tokens,
    refreshToken: tokens.refreshToken || refreshToken,
  };
}

function ensureConfigured(): void {
  if (!isAuthConfigured()) {
    throw new CognitoAuthError(
      "Cognito is not configured. Set NEXT_PUBLIC_COGNITO_CLIENT_ID and NEXT_PUBLIC_COGNITO_REGION.",
    );
  }
}