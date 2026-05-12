"use client";

import * as React from "react";
import { Button } from "@/components/ui/button";

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  React.useEffect(() => {
    if (typeof window !== "undefined") {
      console.error("dashboard error boundary", error);
    }
  }, [error]);

  return (
    <div className="min-h-[50vh] flex items-center justify-center p-6">
      <div className="max-w-md space-y-4 rounded-lg border border-border bg-card p-6 text-center">
        <h2 className="text-lg font-semibold text-foreground">
          Bir şeyler ters gitti
        </h2>
        <p className="text-sm text-muted-foreground">
          Sayfa yüklenirken beklenmedik bir hata oluştu. Sayfayı yeniden yüklemeyi
          deneyin veya tarayıcı önbelleğinizi temizleyin (Ctrl+Shift+R).
        </p>
        {error.digest ? (
          <p className="font-mono text-xs text-muted-foreground/70">
            ref: {error.digest}
          </p>
        ) : null}
        <div className="flex justify-center gap-2 pt-2">
          <Button variant="outline" onClick={() => reset()}>
            Tekrar dene
          </Button>
          <Button onClick={() => window.location.reload()}>Sayfayı yenile</Button>
        </div>
      </div>
    </div>
  );
}
