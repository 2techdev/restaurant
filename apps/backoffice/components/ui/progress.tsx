"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * Minimal progress bar — no Radix dep, just a clipped div. Width is driven
 * by the `value` prop (0..100). Indeterminate state is intentionally not
 * supported; partial UIs that needed it should use a spinner instead.
 */
export const Progress = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & { value?: number }
>(({ className, value = 0, ...rest }, ref) => {
  const v = Math.min(100, Math.max(0, value));
  return (
    <div
      ref={ref}
      role="progressbar"
      aria-valuenow={v}
      aria-valuemin={0}
      aria-valuemax={100}
      className={cn(
        "relative h-2 w-full overflow-hidden rounded-full bg-muted",
        className,
      )}
      {...rest}
    >
      <div
        className="h-full bg-primary transition-[width] duration-500 ease-out"
        style={{ width: `${v}%` }}
      />
    </div>
  );
});
Progress.displayName = "Progress";
