export function cognitoRegion(): string {
  return process.env.NEXT_PUBLIC_COGNITO_REGION?.trim() || "us-east-1";
}

export function cognitoClientId(): string {
  return process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID?.trim() || "";
}

export function cognitoUserPoolId(): string {
  return process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID?.trim() || "";
}

export function cognitoIdentityPoolId(): string {
  return process.env.NEXT_PUBLIC_COGNITO_IDENTITY_POOL_ID?.trim() || "";
}

export function isAuthConfigured(): boolean {
  return cognitoClientId().length > 0 && cognitoRegion().length > 0;
}

export function isDemoFallbackAllowed(): boolean {
  return (
    process.env.NODE_ENV === "development" &&
    process.env.NEXT_PUBLIC_ALLOW_DEMO_FALLBACK === "true"
  );
}

export function cognitoEndpoint(): string {
  return `https://cognito-idp.${cognitoRegion()}.amazonaws.com/`;
}