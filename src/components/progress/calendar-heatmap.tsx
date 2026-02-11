"use client";

import { useMemo } from "react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";

const DAY_LABELS = ["M", "T", "W", "T", "F", "S", "S"];

/** Map intensity string to a heat level 0-3 */
function intensityToLevel(intensity: string): number {
  switch (intensity) {
    case "max":
      return 3;
    case "high":
      return 3;
    case "moderate":
      return 2;
    case "low":
      return 1;
    default:
      return 1;
  }
}

/** Return the ember color at the given opacity tier */
function heatColor(level: number): string {
  switch (level) {
    case 1:
      return "rgba(255, 77, 0, 0.3)";
    case 2:
      return "rgba(255, 77, 0, 0.6)";
    case 3:
      return "#FF4D00";
    default:
      return "#1A1A1A";
  }
}

function legendItem(label: string, color: string) {
  return (
    <div className="flex items-center gap-1.5" key={label}>
      <div
        className="h-3 w-3 rounded-sm"
        style={{ backgroundColor: color }}
      />
      <span className="text-[10px] text-[#71717A]">{label}</span>
    </div>
  );
}

export function CalendarHeatmap() {
  const workoutHistory = useAppStore((s) => s.workoutHistory);

  const { weeks, today } = useMemo(() => {
    // Build a map of date -> intensity level from workout history
    const dateMap: Record<string, number> = {};
    workoutHistory.forEach((w) => {
      dateMap[w.date] = intensityToLevel(w.intensity);
    });

    // February 2026
    const year = 2026;
    const month = 1; // 0-indexed: January=0, February=1
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const todayStr = "2026-02-11";

    // Build day cells for the month
    const firstDayOfMonth = new Date(year, month, 1);
    // getDay() returns 0=Sun, convert to Mon=0 format
    let startDow = firstDayOfMonth.getDay() - 1;
    if (startDow < 0) startDow = 6;

    // Build weeks: array of 7-element arrays
    const allWeeks: Array<Array<{ day: number | null; date: string; level: number }>> = [];
    let currentWeek: Array<{ day: number | null; date: string; level: number }> = [];

    // Fill leading empty cells
    for (let i = 0; i < startDow; i++) {
      currentWeek.push({ day: null, date: "", level: 0 });
    }

    for (let d = 1; d <= daysInMonth; d++) {
      const dateStr = `2026-02-${String(d).padStart(2, "0")}`;
      const level = dateMap[dateStr] ?? 0;
      currentWeek.push({ day: d, date: dateStr, level });

      if (currentWeek.length === 7) {
        allWeeks.push(currentWeek);
        currentWeek = [];
      }
    }

    // Fill trailing empty cells
    if (currentWeek.length > 0) {
      while (currentWeek.length < 7) {
        currentWeek.push({ day: null, date: "", level: 0 });
      }
      allWeeks.push(currentWeek);
    }

    return { weeks: allWeeks, today: todayStr };
  }, [workoutHistory]);

  return (
    <div className="rounded-2xl border border-[#2A2A2A] bg-[#141414] p-5">
      {/* Month label */}
      <p className="text-sm font-semibold text-white mb-4">February 2026</p>

      {/* Day-of-week header */}
      <div className="grid grid-cols-7 gap-1.5 mb-1.5">
        {DAY_LABELS.map((label, i) => (
          <div
            key={`${label}-${i}`}
            className="flex items-center justify-center text-[10px] font-medium text-[#71717A] h-5"
          >
            {label}
          </div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="flex flex-col gap-1.5">
        {weeks.map((week, wi) => (
          <div key={wi} className="grid grid-cols-7 gap-1.5">
            {week.map((cell, ci) => {
              if (cell.day === null) {
                return <div key={`empty-${wi}-${ci}`} className="aspect-square" />;
              }

              const isToday = cell.date === today;

              return (
                <div
                  key={cell.date}
                  className={cn(
                    "aspect-square rounded-[5px] transition-colors relative flex items-center justify-center",
                    isToday && "ring-1 ring-white/40"
                  )}
                  style={{ backgroundColor: heatColor(cell.level) }}
                >
                  <span
                    className={cn(
                      "text-[9px] font-medium",
                      cell.level > 0 ? "text-white/80" : "text-[#71717A]/60"
                    )}
                  >
                    {cell.day}
                  </span>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* Legend */}
      <div className="flex items-center gap-3 mt-4">
        {legendItem("None", "#1A1A1A")}
        {legendItem("Light", "rgba(255, 77, 0, 0.3)")}
        {legendItem("Moderate", "rgba(255, 77, 0, 0.6)")}
        {legendItem("Intense", "#FF4D00")}
      </div>
    </div>
  );
}
