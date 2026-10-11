"use client";

import { PageHeader } from "@/components/ui/card";
import { MonthlySummary } from "@/components/progress/monthly-summary";
import { CalendarHeatmap } from "@/components/progress/calendar-heatmap";
import { PersonalRecordsBoard } from "@/components/progress/personal-records";
import { WorkoutHistoryList } from "@/components/progress/workout-history-list";
import { BehavioralInsight } from "@/components/progress/behavioral-insight";

export function ProgressPage() {
  return (
    <div className="flex flex-col gap-5 bg-background px-4 pb-8 pt-4">
      <PageHeader title="Progress" subtitle="Your month, records and recent sessions." />
      <MonthlySummary />
      <CalendarHeatmap />
      <PersonalRecordsBoard />
      <WorkoutHistoryList />
      <BehavioralInsight />
    </div>
  );
}
