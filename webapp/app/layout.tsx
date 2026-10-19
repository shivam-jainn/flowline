import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Flowline — Turn what you do into Guides",
  description: "Do a task once. Flowline writes it up as a guide.",
};

const themeInit = `(function(){var t=null;try{t=localStorage.getItem('fl-theme')}catch(e){}if(t!=='light'&&t!=='dark'){t=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light'}document.documentElement.setAttribute('data-theme',t);document.documentElement.style.colorScheme=t})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInit }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
