"use client";

import { RefreshCw, WifiOff, AlertTriangle } from "lucide-react";
import { isDemoFallbackAllowed } from "@/lib/auth-config";
import { useAppStore } from "@/stores/useAppStore";
import { API_DISPLAY_HOST } from "@/lib/forge-api";
import { cn } from "@/lib/utils";

export function DataStatusBanner() {
  const dataLoadState = useAppStore((s) => s.dataLoadState);
  const dataLoadError = useAppStore((s) => s.dataLoadError);
  const loadDashboardFromAPI = useAppStore((s) => s.loadDashboardFromAPI);

  if (dataLoadState === "idle" || dataLoadState === "loaded") {
    return null;
  }

  const isLoading = dataLoadState === "loading";
  const isOffline = dataLoadState === "offline";
  const errorMessage = dataLoadError;

  const title = isLoading
    ? "Syncing your data…"
    : isOffline
      ? isDemoFallbackAllowed()
        ? `Can't reach ${API_DISPLAY_HOST} — showing demo data. Run npm run backend:dev.`
        : "Can't reach the Forge API. Check your connection and try again."
      : errorMessage ?? "Something went wrong";

  const Icon = isLoading ? RefreshCw : isOffline ? WifiOff : AlertTriangle;
  const tint = isLoading ? "text-steel" : isOffline ? "text-warning" : "text-danger";

  return (
    <div
      className={cn(
        "sticky top-0 z-40 flex items-center gap-2 border-b border-border/60",
        "bg-surface/95 px-4 py-2.5 backdrop-blur-md",
      )}
    >
      <Icon size={14} className={cn(tint, isLoading && "animate-spin")} />
      <p className="flex-1 text-xs font-medium text-text-secondary leading-snug">{title}</p>
      {!isLoading && (
        <button
          type="button"
          onClick={() => void loadDashboardFromAPI()}
          className="text-xs font-semibold text-ember shrink-0"
        >
          Retry
        </button>
      )}
    </div>
  );
}