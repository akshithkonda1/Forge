import { describe, expect, it, vi } from "vitest";
import {
  refreshAuthPayload,
  refreshSession,
  shouldRefreshToken,
  signIn,
} from "@/lib/cognito-auth";

function makeJwt(expSeconds: number): string {
  const header = btoa(JSON.stringify({ alg: "none" }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const payload = btoa(JSON.stringify({ exp: expSeconds }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return `${header}.${payload}.signature`;
}

describe("cognito-auth", () => {
  it("shouldRefreshToken returns true near expiry", () => {
    const now = Math.floor(Date.now() / 1000);
    const jwt = makeJwt(now + 120);
    expect(shouldRefreshToken(jwt)).toBe(true);
  });

  it("shouldRefreshToken returns false when token is fresh", () => {
    const now = Math.floor(Date.now() / 1000);
    const jwt = makeJwt(now + 3600);
    expect(shouldRefreshToken(jwt)).toBe(false);
  });

  it("refreshAuthPayload matches Cognito contract", () => {
    expect(refreshAuthPayload("web-client", "refresh-abc")).toEqual({
      AuthFlow: "REFRESH_TOKEN_AUTH",
      ClientId: "web-client",
      AuthParameters: {
        REFRESH_TOKEN: "refresh-abc",
      },
    });
  });

  it("signIn sends USER_PASSWORD_AUTH payload", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        AuthenticationResult: {
          IdToken: "id-token",
          AccessToken: "access-token",
          RefreshToken: "refresh-token",
        },
      }),
    });

    vi.stubEnv("NEXT_PUBLIC_COGNITO_CLIENT_ID", "web-client");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_REGION", "us-east-1");

    const tokens = await signIn("user@example.com", "secret", fetchMock);
    expect(tokens.idToken).toBe("id-token");
    expect(fetchMock).toHaveBeenCalledOnce();

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const body = JSON.parse(String(init.body));
    expect(body.AuthFlow).toBe("USER_PASSWORD_AUTH");
    expect(body.ClientId).toBe("web-client");
    expect(body.AuthParameters.USERNAME).toBe("user@example.com");
  });

  it("refreshSession preserves refresh token when Cognito omits it", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        AuthenticationResult: {
          IdToken: "new-id",
          AccessToken: "new-access",
        },
      }),
    });

    vi.stubEnv("NEXT_PUBLIC_COGNITO_CLIENT_ID", "web-client");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_REGION", "us-east-1");

    const tokens = await refreshSession("existing-refresh", fetchMock);
    expect(tokens.refreshToken).toBe("existing-refresh");
  });
});