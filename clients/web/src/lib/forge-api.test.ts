import { beforeEach, describe, expect, it, vi } from "vitest";
import * as authSession from "@/lib/auth-session";
import { forgeFetch } from "@/lib/forge-api";

describe("forgeFetch", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.stubEnv("NEXT_PUBLIC_API_URL", "http://127.0.0.1:3001");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_CLIENT_ID", "web-client");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_REGION", "us-east-1");
  });

  it("attaches Authorization header when session token exists", async () => {
    vi.spyOn(authSession, "getAuthorizationHeader").mockReturnValue("Bearer id-token");
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await forgeFetch("/dashboard/today");

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(new Headers(init.headers).get("Authorization")).toBe("Bearer id-token");
  });

  it("retries once after refreshing on 401", async () => {
    vi.spyOn(authSession, "getAuthorizationHeader").mockReturnValue("Bearer stale");
    vi.spyOn(authSession, "refreshSessionIfNeeded").mockResolvedValue(true);

    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 401, json: async () => ({ message: "Unauthorized" }) })
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ ok: true }) });
    vi.stubGlobal("fetch", fetchMock);

    const result = await forgeFetch<{ ok: boolean }>("/me");
    expect(result.ok).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(authSession.refreshSessionIfNeeded).toHaveBeenCalledWith(true);
  });

  it("clears session when refresh fails on 401", async () => {
    vi.spyOn(authSession, "getAuthorizationHeader").mockReturnValue("Bearer stale");
    vi.spyOn(authSession, "refreshSessionIfNeeded").mockResolvedValue(false);
    const clearSpy = vi.spyOn(authSession, "clearAuthSession").mockImplementation(() => {});

    const fetchMock = vi.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ message: "Unauthorized" }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await expect(forgeFetch("/me")).rejects.toMatchObject({ status: 401 });
    expect(clearSpy).toHaveBeenCalledOnce();
  });
});