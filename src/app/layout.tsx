import type { Metadata, Viewport } from "next";
import { Plus_Jakarta_Sans, JetBrains_Mono } from "next/font/google";
import "./globals.css";

import { MotionConfigProvider } from "@/components/shared/motion-config-provider";
import { ToastHost } from "@/components/shared/toast-host";

const sans = Plus_Jakarta_Sans({
  subsets: ["latin"],
  variable: "--font-forge-sans",
  display: "swap",
  weight: ["400", "500", "600", "700"],
});

const mono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-forge-mono",
  display: "swap",
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  title: "Forge — ARIA Coaching",
  description:
    "Forge unifies your health signals. ARIA coaches from inside the life you already have.",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Forge",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#0A0A0A",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`dark ${sans.variable} ${mono.variable}`}>
      <body className="min-h-[100dvh] bg-[#050505] font-sans antialiased">
        <MotionConfigProvider>
          {children}
          <ToastHost />
        </MotionConfigProvider>
      </body>
    </html>
  );
}
