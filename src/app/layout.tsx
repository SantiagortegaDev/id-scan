import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "ID Scan Colombia - Escáner de Cédula",
  description: "Escáner de cédula de ciudadanía colombiana. Lee el código de barras PDF417 del reverso de tu cédula.",
  keywords: ["ID Scan", "Colombia", "Cédula", "PDF417", "barcode scanner"],
  authors: [{ name: "ID Scan Colombia" }],
  icons: {
    icon: "https://z-cdn.chatglm.cn/z-ai/static/logo.svg",
  },
  openGraph: {
    title: "ID Scan Colombia",
    description: "Escáner de cédula de ciudadanía colombiana",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "ID Scan Colombia",
    description: "Escáner de cédula de ciudadanía colombiana",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased bg-background text-foreground`}
      >
        {children}
        <Toaster />
      </body>
    </html>
  );
}
