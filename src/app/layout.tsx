import type { Metadata, Viewport } from "next";
import "./globals.css";

import { ToastHost } from "@/components/shared/toast-host";

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
    <html lang="en" className="dark">
      <body className="min-h-[100dvh] bg-[#050505] antialiased">
        {children}
        <ToastHost />
      </body>
    </html>
  );
}
