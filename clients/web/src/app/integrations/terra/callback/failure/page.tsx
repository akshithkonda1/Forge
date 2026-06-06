"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { X } from "lucide-react";
import { clearConnectReturn, readConnectReturn } from "@/lib/device-connect";
import { useAppStore } from "@/stores/useAppStore";

export default function DeviceConnectFailurePage() {
  const router = useRouter();
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  useEffect(() => {
    const { returnPath, returnTab } = readConnectReturn();
    clearConnectReturn();

    const timer = window.setTimeout(() => {
      if (returnTab) {
        setActiveTab(returnTab);
      }
      router.replace(returnPath);
    }, 2200);

    return () => window.clearTimeout(timer);
  }, [router, setActiveTab]);

  return (
    <div className="flex min-h-[100dvh] flex-col items-center justify-center bg-background px-6 text-center">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-danger/10"
      >
        <X size={36} className="text-danger" />
      </motion.div>
      <h1 className="mb-2 text-2xl font-bold text-text-primary">Connection cancelled</h1>
      <p className="max-w-sm text-text-tertiary">
        No worries — you can try again from Settings whenever you&apos;re ready.
      </p>
    </div>
  );
}