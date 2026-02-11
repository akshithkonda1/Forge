"use client";

import { MonthlySummary } from "@/components/progress/monthly-summary";
import { CalendarHeatmap } from "@/components/progress/calendar-heatmap";
import { PersonalRecordsBoard } from "@/components/progress/personal-records";
import { WorkoutHistoryList } from "@/components/progress/workout-history-list";
import { BehavioralInsight } from "@/components/progress/behavioral-insight";

export function ProgressPage() {
  return (
    <div className="bg-[#0A0A0A] px-4 pb-8 overflow-y-auto">
      {/* Page title */}
      <h1 className="text-2xl font-bold text-white mb-6 pt-4">Progress</h1>

      {/* Sections */}
      <div className="flex flex-col gap-6">
        <MonthlySummary />
        <CalendarHeatmap />
        <PersonalRecordsBoard />
        <WorkoutHistoryList />
        <BehavioralInsight />
      </div>
    </div>
  );
}
