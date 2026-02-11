import * as React from "react";
import { cn } from "@/lib/utils";

interface MetricPillProps {
  icon: React.ReactNode;
  label: string;
  value: string | number;
  trend?: "up" | "down" | "neutral";
  className?: string;
}

function TrendArrow({ trend }: { trend: "up" | "down" }) {
  if (trend === "up") {
    return (
      <svg
        width="12"
        height="12"
        viewBox="0 0 12 12"
        fill="none"
        className="ml-1"
      >
        <path
          d="M6 2.5L9.5 6.5H2.5L6 2.5Z"
          fill="#22C55E"
        />
      </svg>
    );
  }

  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 12 12"
      fill="none"
      className="ml-1"
    >
      <path
        d="M6 9.5L2.5 5.5H9.5L6 9.5Z"
        fill="#EF4444"
      />
    </svg>
  );
}

export function MetricPill({
  icon,
  label,
  value,
  trend,
  className,
}: MetricPillProps) {
  return (
    <div
      className={cn(
        "inline-flex items-center gap-2 rounded-full bg-[#141414] border border-[#2A2A2A] px-3 py-1.5",
        className
      )}
    >
      <span className="flex-shrink-0 text-[#A1A1AA]">{icon}</span>
      <span className="text-xs font-medium text-white">{value}</span>
      {trend && trend !== "neutral" && <TrendArrow trend={trend} />}
      <span className="text-xs text-[#A1A1AA]">{label}</span>
    </div>
  );
}
