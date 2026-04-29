"use client";

import * as React from "react";

type ToastVariant = "default" | "destructive";

export interface ToastItem {
  id: string;
  title?: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
}

type ToastInput = Omit<ToastItem, "id"> & { id?: string };

interface ToastContextValue {
  toasts: ToastItem[];
  toast: (t: ToastInput) => void;
  dismiss: (id: string) => void;
}

const ToastContext = React.createContext<ToastContextValue | null>(null);

export function useToastContext() {
  const ctx = React.useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used within <Toaster />");
  return ctx;
}

export function useToast() {
  const ctx = useToastContext();
  return { toast: ctx.toast, dismiss: ctx.dismiss, toasts: ctx.toasts };
}

export { ToastContext };
