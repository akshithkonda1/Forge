import { env } from "@/lib/env";
import type { ApiError } from "@/types";

export class ApiRequestError extends Error {
  readonly status: number;
  readonly code?: string;
  readonly details?: Record<string, unknown>;

  constructor(status: number, error: ApiError) {
    super(error.message);
    this.name = "ApiRequestError";
    this.status = status;
    this.code = error.code;
    this.details = error.details;
  }
}

interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  /** Bearer token; omitted in auth-disabled dev mode. */
  token?: string | null;
  signal?: AbortSignal;
}

/** Thin typed fetch wrapper around the Forge backend. */
export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, token, signal } = options;

  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;

  const response = await fetch(`${env.apiUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  });

  const text = await response.text();
  let data: unknown = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      // Non-JSON body; surface the raw text on error below.
    }
  }

  if (!response.ok) {
    const fallback: ApiError = { message: text || response.statusText };
    const error = (data && typeof data === "object" ? (data as ApiError) : fallback) ?? fallback;
    throw new ApiRequestError(response.status, {
      message: error.message ?? fallback.message,
      code: error.code,
      details: error.details,
    });
  }

  return data as T;
}
