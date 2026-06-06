"use client";

import { useCallback, useEffect, useState } from "react";
import { forgeAPI, ForgeAPIError } from "@/lib/forge-api";
import {
  connectionForDevice,
  isDeviceConnected,
  providerForDevice,
  startDeviceConnect,
  type WearableDeviceId,
} from "@/lib/device-connect";
import type { IntegrationConnection } from "@/types";

interface ConnectionServiceStatus {
  configured: boolean;
  connected: boolean;
  provider?: string;
}

export function useDeviceConnections(
  connections: IntegrationConnection[],
  options?: { refreshProfile?: () => Promise<void> },
) {
  const [status, setStatus] = useState<ConnectionServiceStatus | null>(null);
  const [loadingStatus, setLoadingStatus] = useState(true);
  const [connectingDevice, setConnectingDevice] = useState<WearableDeviceId | null>(null);
  const [syncingProvider, setSyncingProvider] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refreshStatus = useCallback(async () => {
    setLoadingStatus(true);
    try {
      const serviceStatus = await forgeAPI.getDeviceConnectionStatus();
      setStatus({
        configured: serviceStatus.configured,
        connected: serviceStatus.connected,
        provider: serviceStatus.provider,
      });
      setError(null);
    } catch (err) {
      setStatus({ configured: false, connected: false });
      if (err instanceof ForgeAPIError && err.status !== 503) {
        setError(err.message);
      }
    } finally {
      setLoadingStatus(false);
    }
  }, []);

  useEffect(() => {
    void refreshStatus();
  }, [refreshStatus]);

  useEffect(() => {
    const handleFocus = () => {
      void refreshStatus();
      void options?.refreshProfile?.();
    };
    window.addEventListener("focus", handleFocus);
    return () => window.removeEventListener("focus", handleFocus);
  }, [options?.refreshProfile, refreshStatus]);

  const connectDevice = useCallback(
    async (connectOptions: {
      deviceId?: WearableDeviceId;
      returnPath: string;
      returnTab?: string;
    }) => {
      setError(null);
      setConnectingDevice(connectOptions.deviceId ?? null);
      try {
        await startDeviceConnect(connectOptions);
      } catch (err) {
        setConnectingDevice(null);
        if (err instanceof ForgeAPIError && err.status === 503) {
          setError("Wearable connections are not configured yet on this backend.");
          return;
        }
        setError(err instanceof Error ? err.message : "Failed to start device connection.");
      }
    },
    [],
  );

  const syncConnection = useCallback(
    async (provider: string) => {
      setError(null);
      setSyncingProvider(provider);
      try {
        await forgeAPI.syncIntegration(provider);
        await options?.refreshProfile?.();
        await refreshStatus();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to sync device data.");
      } finally {
        setSyncingProvider(null);
      }
    },
    [options?.refreshProfile, refreshStatus],
  );

  const syncDevice = useCallback(
    async (deviceId: WearableDeviceId) => {
      const provider = providerForDevice(deviceId);
      if (!provider || provider === "manual") {
        setError("Sync is not available for this device yet.");
        return;
      }
      await syncConnection(provider);
    },
    [syncConnection],
  );

  const handleConnectionAction = useCallback(
    async (connection: IntegrationConnection) => {
      if (connection.status === "connected" || connection.status === "syncing") {
        if (connection.provider === "manual") {
          setError("Sync is not available for this device yet.");
          return;
        }
        await syncConnection(connection.provider);
        return;
      }
      await connectDevice({ returnPath: "/", returnTab: "profile" });
    },
    [connectDevice, syncConnection],
  );

  return {
    status,
    loadingStatus,
    connectingDevice,
    syncingProvider,
    error,
    isDeviceConnected: (deviceId: WearableDeviceId) => isDeviceConnected(deviceId, connections),
    connectionForDevice: (deviceId: WearableDeviceId) =>
      connectionForDevice(deviceId, connections),
    connectDevice,
    syncDevice,
    syncConnection,
    handleConnectionAction,
    refreshStatus,
    clearError: () => setError(null),
  };
}