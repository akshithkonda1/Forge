export const cognitoRegion =
  process.env.NEXT_PUBLIC_COGNITO_REGION?.trim() ?? "us-east-1";

export const cognitoClientId =
  process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID?.trim() ?? "";

export const cognitoUserPoolId =
  process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID?.trim() ?? "";

export const cognitoIdentityPoolId =
  process.env.NEXT_PUBLIC_COGNITO_IDENTITY_POOL_ID?.trim() ?? "";

export function isAuthConfigured(): boolean {
  return cognitoClientId.length > 0 && cognitoRegion.length > 0;
}

export function isDemoFallbackAllowed(): boolean {
  return (
    process.env.NODE_ENV === "development" &&
    process.env.NEXT_PUBLIC_ALLOW_DEMO_FALLBACK === "true"
  );
}

export function cognitoEndpoint(): string {
  return `https://cognito-idp.${cognitoRegion}.amazonaws.com/`;
}