"use client";

/**
 * Refunds — UI only (in-memory store).
 *
 * Backend `/api/v1/refunds` does not exist yet. The client persists draft
 * refund records to localStorage so the operator can sketch the workflow
 * with the design team. Once Agent A wires the endpoint, swap the
 * `useRefundStore` calls to TanStack Query mutations and drop the toast
 * banner; the form / table layout doesn't have to change.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Plus, AlertCircle, Check, X } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";
import { formatChf, formatDateTime } from "@/lib/utils";

interface RefundDraft {
  id: string;
  order_id: string;
  amount_cents: number;
  reason: string;
  requested_by: string;
  status: "pending" | "approved" | "rejected";
  created_at: string;
}

const STORAGE_KEY = "bo.refunds.drafts.v1";

function load(): RefundDraft[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as RefundDraft[]) : [];
  } catch {
    return [];
  }
}
function save(items: RefundDraft[]) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    // ignore
  }
}

const RefundFormSchema = z.object({
  order_id: z
    .string()
    .min(4, "geçersiz")
    .regex(/^[#a-zA-Z0-9-]+$/, "geçersiz"),
  amount_chf: z.coerce.number().min(0.01),
  reason: z.string().min(3),
  requested_by: z.string().min(1),
});
type RefundFormInput = z.infer<typeof RefundFormSchema>;

export function RefundsClient() {
  const t = useTranslations("orders.refunds");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [items, setItems] = React.useState<RefundDraft[]>([]);
  const [open, setOpen] = React.useState(false);

  React.useEffect(() => {
    setItems(load());
  }, []);

  const persist = (next: RefundDraft[]) => {
    setItems(next);
    save(next);
  };

  const form = useForm<RefundFormInput>({
    resolver: zodResolver(RefundFormSchema),
    defaultValues: {
      order_id: "",
      amount_chf: 0,
      reason: "",
      requested_by: "",
    },
  });

  const onCreate = (input: RefundFormInput) => {
    const draft: RefundDraft = {
      id: crypto.randomUUID(),
      order_id: input.order_id.replace(/^#/, ""),
      amount_cents: Math.round(input.amount_chf * 100),
      reason: input.reason,
      requested_by: input.requested_by,
      status: "pending",
      created_at: new Date().toISOString(),
    };
    persist([draft, ...items]);
    setOpen(false);
    form.reset();
    toast({ title: t("createdToast") });
  };

  const setStatus = (id: string, status: RefundDraft["status"]) => {
    persist(
      items.map((it) => (it.id === id ? { ...it, status } : it))
    );
  };

  return (
    <div className="space-y-4">
      <Alert>
        <AlertCircle className="h-4 w-4" />
        <AlertDescription>{t("plannedBackend")}</AlertDescription>
      </Alert>

      <div className="flex justify-end">
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          {t("newRefund")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>
        {items.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {t("emptyState")}
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.orderId")}</TableHead>
                <TableHead>{t("col.amount")}</TableHead>
                <TableHead>{t("col.reason")}</TableHead>
                <TableHead>{t("col.requestedBy")}</TableHead>
                <TableHead>{t("col.status")}</TableHead>
                <TableHead>{t("col.createdAt")}</TableHead>
                <TableHead className="text-right">{t("col.actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-mono text-[12px]">
                    #{r.order_id}
                  </TableCell>
                  <TableCell className="font-mono tabular-nums">
                    {formatChf(r.amount_cents / 100)}
                  </TableCell>
                  <TableCell className="max-w-[280px] truncate">
                    {r.reason}
                  </TableCell>
                  <TableCell>{r.requested_by}</TableCell>
                  <TableCell>
                    <StatusBadge
                      variant={
                        r.status === "approved"
                          ? "success"
                          : r.status === "rejected"
                            ? "error"
                            : "warning"
                      }
                      withDot
                    >
                      {t(`status.${r.status}`)}
                    </StatusBadge>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {formatDateTime(r.created_at)}
                  </TableCell>
                  <TableCell className="text-right">
                    {r.status === "pending" ? (
                      <div className="flex gap-1 justify-end">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => setStatus(r.id, "approved")}
                        >
                          <Check className="h-3.5 w-3.5" />
                          {t("approve")}
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-error border-error/30"
                          onClick={() => setStatus(r.id, "rejected")}
                        >
                          <X className="h-3.5 w-3.5" />
                          {t("reject")}
                        </Button>
                      </div>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("newRefund")}</DialogTitle>
            <DialogDescription>{t("formHint")}</DialogDescription>
          </DialogHeader>
          <form
            onSubmit={form.handleSubmit(onCreate)}
            className="space-y-3 pt-2"
          >
            <div className="space-y-1">
              <Label>{t("col.orderId")}</Label>
              <Input
                placeholder="#4729"
                {...form.register("order_id")}
              />
              {form.formState.errors.order_id && (
                <p className="text-xs text-error">
                  {form.formState.errors.order_id.message}
                </p>
              )}
            </div>
            <div className="space-y-1">
              <Label>{t("col.amount")} (CHF)</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                {...form.register("amount_chf")}
              />
              {form.formState.errors.amount_chf && (
                <p className="text-xs text-error">{tCommon("error")}</p>
              )}
            </div>
            <div className="space-y-1">
              <Label>{t("col.reason")}</Label>
              <textarea
                rows={3}
                className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                placeholder={t("reasonPlaceholder")}
                {...form.register("reason")}
              />
              {form.formState.errors.reason && (
                <p className="text-xs text-error">
                  {form.formState.errors.reason.message}
                </p>
              )}
            </div>
            <div className="space-y-1">
              <Label>{t("col.requestedBy")}</Label>
              <Input {...form.register("requested_by")} />
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setOpen(false)}
              >
                {tCommon("cancel")}
              </Button>
              <Button type="submit" disabled={form.formState.isSubmitting}>
                {tCommon("save")}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
