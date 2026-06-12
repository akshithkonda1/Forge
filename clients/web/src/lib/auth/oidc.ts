import { WebStorageStateStore } from "oidc-client-ts";
import type { AuthProviderProps } from "react-oidc-context";
import { cognitoAuthority, env } from "@/lib/env";

// OIDC config for Cognito Hosted UI (Authorization Code + PKCE).
//
// We supply explicit `metadata` pointing at the Hosted UI domain so the flow
// does not depend on Cognito's discovery document (whose endpoints/end_session
// support is inconsistent). When no Hosted UI domain is configured (e.g. local
// auth-disabled dev), metadata is omitted and the provider stays inert.
export const oidcConfig: AuthProviderProps = {
  authority: cognitoAuthority,
  client_id: env.cognito.clientId,
  redirect_uri: env.cognito.redirectUri,
  response_type: "code",
  scope: "openid email profile",
  automaticSilentRenew: true,
  userStore:
    typeof window !== "undefined"
      ? new WebStorageStateStore({ store: window.localStorage })
      : undefined,
  metadata: env.cognito.hostedUiDomain
    ? {
        issuer: cognitoAuthority,
        authorization_endpoint: `${env.cognito.hostedUiDomain}/oauth2/authorize`,
        token_endpoint: `${env.cognito.hostedUiDomain}/oauth2/token`,
        userinfo_endpoint: `${env.cognito.hostedUiDomain}/oauth2/userInfo`,
        end_session_endpoint: `${env.cognito.hostedUiDomain}/logout`,
        jwks_uri: `${cognitoAuthority}/.well-known/jwks.json`,
      }
    : undefined,
  // Strip ?code&state from the URL after a successful sign-in callback.
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, window.location.pathname);
  },
};

// Cognito's /logout expects `client_id` + `logout_uri` rather than the standard
// OIDC end-session params, so we redirect manually.
export function cognitoLogout(): void {
  const params = new URLSearchParams({
    client_id: env.cognito.clientId,
    logout_uri: env.cognito.logoutUri,
  });
  window.location.assign(`${env.cognito.hostedUiDomain}/logout?${params.toString()}`);
}
