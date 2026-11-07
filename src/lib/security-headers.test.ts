import { describe, expect, it } from "vitest";
import nextConfig from "../../next.config";

describe("BH-18 security headers", () => {
  it("sets CSP, frame-ancestors, and Referrer-Policy", async () => {
    const headersFn = nextConfig.headers;
    expect(headersFn).toBeTypeOf("function");
    const rules = await headersFn!();
    const headers = Object.fromEntries(
      rules[0].headers.map((row) => [row.key, row.value])
    );
    expect(headers["Content-Security-Policy"]).toContain("default-src 'self'");
    expect(headers["Content-Security-Policy"]).toContain("frame-ancestors 'none'");
    expect(headers["X-Frame-Options"]).toBe("DENY");
    expect(headers["Referrer-Policy"]).toBe("strict-origin-when-cross-origin");
    expect(headers["X-Content-Type-Options"]).toBe("nosniff");
  });
});
