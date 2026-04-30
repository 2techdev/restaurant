import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * StatusBadge — soft-tinted pill for status / diff signaling.
 * Cherry-picked from designer canvas pattern: solid foreground + soft
 * background so badges stay readable on both light and dark surfaces.
 *
 * Use:
 *   <StatusBadge variant="success">Tamamlandı</StatusBadge>
 *   <StatusBadge variant="diff-add">+ Yeni ürün</StatusBadge>
 */
export type StatusBadgeVariant =
  | "success"
  | "warning"
  | "error"
  | "info"
  | "neutral"
  | "diff-add"
  | "diff-mod"
  | "diff-del";

const VARIANT_CLASS: Record<StatusBadgeVariant, string> = {
  success: "bg-success-soft text-success",
  warning: "bg-warning-soft text-warning",
  error: "bg-error-soft text-error",
  info: "bg-info-soft text-info",
  neutral: "bg-muted text-muted-foreground",
  "diff-add": "bg-diff-add-bg text-diff-add",
  "diff-mod": "bg-diff-mod-bg text-diff-mod",
  "diff-del": "bg-diff-del-bg text-diff-del",
};

export interface StatusBadgeProps
  extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: StatusBadgeVariant;
  /** Render a leading dot the same color as the foreground. */
  withDot?: boolean;
}

export function StatusBadge({
  variant = "neutral",
  withDot = false,
  className,
  children,
  ...props
}: StatusBadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 h-5 px-2 text-[11px] font-medium rounded-full whitespace-nowrap",
        VARIANT_CLASS[variant],
        className
      )}
      {...props}
    >
      {withDot && (
        <span
          aria-hidden
          className="h-1.5 w-1.5 rounded-full bg-current"
        />
      )}
      {children}
    </span>
  );
}
