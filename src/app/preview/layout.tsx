import type { Metadata } from "next";
import localFont from "next/font/local";
import { PreviewSeed } from "@/components/preview/seed";
import "./preview.css";

const geist = localFont({
  src: [
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/Geist-Regular.ttf",
      weight: "400",
      style: "normal",
    },
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/Geist-Medium.ttf",
      weight: "500",
      style: "normal",
    },
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/Geist-SemiBold.ttf",
      weight: "600",
      style: "normal",
    },
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/Geist-Bold.ttf",
      weight: "700",
      style: "normal",
    },
  ],
  variable: "--font-preview-geist",
  display: "swap",
});

const serif = localFont({
  src: [
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/InstrumentSerif-Regular.ttf",
      weight: "400",
      style: "normal",
    },
    {
      path: "../../../ForgeSwift/ForgeCore/Sources/ForgeCore/Resources/Fonts/InstrumentSerif-Italic.ttf",
      weight: "400",
      style: "italic",
    },
  ],
  variable: "--font-preview-serif",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Forge UI preview · PR #472",
  description:
    "iPhone-sized gallery of Forge after the PR #472 frontend pass. Sample data. Not live.",
  robots: { index: false, follow: false },
};

export default function PreviewLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={`preview-root ${geist.variable} ${serif.variable}`}>
      <PreviewSeed />
      {children}
    </div>
  );
}
