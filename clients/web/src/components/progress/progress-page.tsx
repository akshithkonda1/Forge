"use client";

import { MonthlySummary } from "@/components/progress/monthly-summary";
import { CalendarHeatmap } from "@/components/progress/calendar-heatmap";
import { PersonalRecordsBoard } from "@/components/progress/personal-records";
import { WorkoutHistoryList } from "@/components/progress/workout-history-list";
import { BehavioralInsight } from "@/components/progress/behavioral-insight";

export function ProgressPage() {
  return (
    <div className="overflow-y-auto bg-background px-4 pb-8">
      <h1 className="mb-6 pt-4 text-2xl font-bold text-text-primary">Progress</h1>

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
