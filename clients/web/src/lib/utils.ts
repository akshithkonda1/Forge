import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatNumber(num: number): string {
  if (num >= 1000) {
    return `${(num / 1000).toFixed(1)}k`;
  }
  return num.toString();
}

export function getReadinessColor(score: number): string {
  if (score >= 80) return "#22C55E";
  if (score >= 60) return "#FF4D00";
  if (score >= 40) return "#EAB308";
  return "#EF4444";
}

export function getReadinessLabel(score: number): string {
  if (score >= 80) return "Primed";
  if (score >= 60) return "Good";
  if (score >= 40) return "Fair";
  return "Rest Day";
}
