// Centralized, typed access to the public client configuration.
// All values are inlined at build time by Next.js (NEXT_PUBLIC_ prefix).

function flag(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined) return fallback;
  return value === "true" || value === "1";
}

export const env = {
  apiUrl: process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001",
  // Default true so `pnpm dev` against the local backend works without Cognito.
  authDisabled: flag(process.env.NEXT_PUBLIC_AUTH_DISABLED, true),
  cognito: {
    region: process.env.NEXT_PUBLIC_COGNITO_REGION ?? "us-east-1",
    userPoolId: process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID ?? "",
    clientId: process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? "",
    hostedUiDomain: process.env.NEXT_PUBLIC_COGNITO_HOSTED_UI_DOMAIN ?? "",
    redirectUri:
      process.env.NEXT_PUBLIC_COGNITO_REDIRECT_URI ?? "http://localhost:3000/auth/callback",
    logoutUri: process.env.NEXT_PUBLIC_COGNITO_LOGOUT_URI ?? "http://localhost:3000/",
  },
} as const;

// Cognito user pool issuer — used as the OIDC `authority`.
export const cognitoAuthority = `https://cognito-idp.${env.cognito.region}.amazonaws.com/${env.cognito.userPoolId}`;
