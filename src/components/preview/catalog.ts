export type PreviewSlug =
  | "onboarding-meet"
  | "onboarding-health"
  | "onboarding-how-are-you"
  | "tutorial-beginner"
  | "tutorial-competitor"
  | "home"
  | "lifestyle"
  | "sleep"
  | "stats"
  | "chat"
  | "memory"
  | "train";

export type PreviewTab = "home" | "train" | "life" | "chat" | "sleep" | "stats" | "you" | null;

export type PreviewEntry = {
  slug: PreviewSlug;
  title: string;
  caption: string;
  tab: PreviewTab;
};

export const PREVIEW_CATALOG: PreviewEntry[] = [
  {
    slug: "onboarding-meet",
    title: "Onboarding · Meet",
    caption: "First beat. Procedural ARIA mark, no PNG.",
    tab: null,
  },
  {
    slug: "onboarding-health",
    title: "Onboarding · Permissions",
    caption: "Health, Calendar, Contacts, Reminders — Skip always visible.",
    tab: null,
  },
  {
    slug: "onboarding-how-are-you",
    title: "Onboarding · How are you doing",
    caption: "First-bond invite. One true sentence.",
    tab: "chat",
  },
  {
    slug: "tutorial-beginner",
    title: "Tutorial · Beginner",
    caption: "Opening branches on experience. Skip always here.",
    tab: "home",
  },
  {
    slug: "tutorial-competitor",
    title: "Tutorial · Competitive athlete",
    caption: "Load, sleep, next session — not a sales pitch.",
    tab: "home",
  },
  {
    slug: "home",
    title: "Home",
    caption: "Jordan’s morning, the week, the day’s picture, one next move.",
    tab: "home",
  },
  {
    slug: "lifestyle",
    title: "Lifestyle",
    caption: "Sleep, food, stress and people. Movement is one tile.",
    tab: "life",
  },
  {
    slug: "sleep",
    title: "Sleep",
    caption: "Last night in plain words. Sizes today — never grades you.",
    tab: "sleep",
  },
  {
    slug: "stats",
    title: "Stats",
    caption: "Jordan’s progress. History, PRs, the training story.",
    tab: "stats",
  },
  {
    slug: "chat",
    title: "ARIA · Personality",
    caption: "Coach, Friend, Drill Sergeant. Changes the next reply.",
    tab: "chat",
  },
  {
    slug: "memory",
    title: "Settings · Aria’s memory",
    caption: "On this phone. Edit or delete anything remembered.",
    tab: "you",
  },
  {
    slug: "train",
    title: "Train · Discovery",
    caption: "Session hub plus a move that fits the gear you have.",
    tab: "train",
  },
];

export function previewEntry(slug: string): PreviewEntry | undefined {
  return PREVIEW_CATALOG.find((entry) => entry.slug === slug);
}
