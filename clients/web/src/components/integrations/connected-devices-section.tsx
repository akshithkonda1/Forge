"use client";

import { useState } from "react";
import { Loader2, Plus, RefreshCw, Watch } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { useDeviceConnections } from "@/hooks/useDeviceConnections";
import type { WearableDeviceId } from "@/lib/device-connect";
import { DeviceGrid } from "@/components/integrations/device-grid";
import type { IntegrationConnection } from "@/types";

function connectionStatusLabel(connection: IntegrationConnection) {
  switch (connection.status) {
    case "connected":
      return "Connected";
    case "syncing":
      return "Syncing";
    case "error":
      return "Error";
    default:
      return "Needs auth";
  }
}

function connectionStatusColor(connection: IntegrationConnection) {
  switch (connection.status) {
    case "connected":
      return "bg-success";
    case "syncing":
      return "bg-ember";
    case "error":
      return "bg-danger";
    default:
      return "bg-text-muted";
  }
}

function connectionActionLabel(connection: IntegrationConnection, syncing: boolean) {
  if (syncing) return "Syncing...";
  if (connection.status === "connected" || connection.status === "syncing") {
    return "Tap to sync";
  }
  return "Tap to connect";
}

interface ConnectedDevicesSectionProps {
  SectionHeader: React.ComponentType<{ children: React.ReactNode }>;
  SectionCard: React.ComponentType<{ children: React.ReactNode }>;
  SettingsRow: React.ComponentType<{
    icon?: React.ReactNode;
    iconColor?: string;
    label: string;
    value?: React.ReactNode;
    showChevron?: boolean;
    onClick?: () => void;
  }>;
}

export function ConnectedDevicesSection({
  SectionHeader,
  SectionCard,
  SettingsRow,
}: ConnectedDevicesSectionProps) {
  const connections = useAppStore((s) => s.connections);
  const userProfile = useAppStore((s) => s.userProfile);
  const refreshProfileFromAPI = useAppStore((s) => s.refreshProfileFromAPI);
  const [showAddGrid, setShowAddGrid] = useState(false);

  const {
    status,
    loadingStatus,
    connectingDevice,
    syncingProvider,
    error,
    isDeviceConnected,
    connectDevice,
    handleConnectionAction,
    refreshStatus,
  } = useDeviceConnections(connections, { refreshProfile: refreshProfileFromAPI });

  const visibleConnections =
    connections.length > 0
      ? connections
      : userProfile.connectedDevices.map((name) => ({
          provider: "manual" as const,
          displayName: name,
          status: "connected" as const,
        }));

  const handleAddConnect = (deviceId: WearableDeviceId) => {
    void connectDevice({
      deviceId,
      returnPath: "/",
      returnTab: "profile",
    });
  };

  return (
    <>
      <SectionHeader>Connected Devices</SectionHeader>
      <SectionCard>
        {visibleConnections.length === 0 ? (
          <div className="px-4 py-4 text-sm text-text-tertiary">
            No devices connected yet. Add a wearable to sync sleep, activity, and recovery data.
          </div>
        ) : (
          visibleConnections.map((connection) => {
            const syncing = syncingProvider === connection.provider;
            return (
              <SettingsRow
                key={`${connection.provider}-${connection.displayName}`}
                icon={<Watch size={18} />}
                iconColor="text-steel"
                label={connection.displayName}
                onClick={() => void handleConnectionAction(connection)}
                value={
                  <span className="inline-flex flex-col items-end gap-0.5 text-xs">
                    <span className="inline-flex items-center gap-1.5">
                      <span
                        className={cn(
                          "inline-block h-2 w-2 rounded-full",
                          connectionStatusColor(connection),
                        )}
                      />
                      {syncing ? "Syncing..." : connectionStatusLabel(connection)}
                    </span>
                    <span className="text-text-muted">
                      {connectionActionLabel(connection, syncing)}
                    </span>
                  </span>
                }
              />
            );
          })
        )}

        {!loadingStatus && status && !status.configured && (
          <div className="px-4 py-3 text-xs leading-relaxed text-text-tertiary">
            Device connections are not configured on this API yet.
          </div>
        )}

        {error && <div className="px-4 py-3 text-xs text-danger">{error}</div>}

        <button
          type="button"
          disabled={Boolean(connectingDevice)}
          onClick={() => setShowAddGrid((open) => !open)}
          className="flex w-full items-center gap-3 px-4 py-3 transition-colors active:bg-surface-hover disabled:opacity-60"
        >
          <span className="flex h-8 w-8 items-center justify-center rounded-full border border-dashed border-border-light">
            {connectingDevice ? (
              <Loader2 size={16} className="animate-spin text-ember" />
            ) : (
              <Plus size={16} className="text-text-tertiary" />
            )}
          </span>
          <span className="text-sm font-medium text-ember">
            {showAddGrid ? "Hide device list" : "Add Device"}
          </span>
        </button>

        {showAddGrid && (
          <div className="border-t border-border px-4 py-4">
            <DeviceGrid
              compact
              isDeviceConnected={isDeviceConnected}
              connectingDevice={connectingDevice}
              onConnect={handleAddConnect}
            />
          </div>
        )}

        <button
          type="button"
          onClick={() => {
            void refreshStatus();
            void refreshProfileFromAPI();
          }}
          className="flex w-full items-center justify-center gap-2 px-4 py-2 text-xs text-text-muted transition-colors hover:text-text-secondary"
        >
          <RefreshCw size={12} />
          Refresh devices
        </button>
      </SectionCard>
    </>
  );
}