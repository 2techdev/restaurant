"use client";

/**
 * Discounts (Agent A backend — /api/v1/discounts CRUD).
 * Type: PERCENT | FIXED | BOGO. Optional time window + active toggle.
 */

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Plus,
  Loader2,
  Tag,
  MoreHorizontal,
  Pencil,
  Trash2,
} from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
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

interface Discount {
  id: string;
  tenant_id: string;
  name: string;
  type: "PERCENT" | "FIXED" | "BOGO";
  value: number;
  active: boolean;
  starts_at?: string | null;
  ends_at?: string | null;
}

const FormSchema = z.object({
  name: z.string().min(1),
  type: z.enum(["PERCENT", "FIXED", "BOGO"]),
  value: z.coerce.number().min(0),
  active: z.boolean(),
  starts_at: z.string().optional(),
  ends_at: z.string().optional(),
});
type FormInput = z.infer<typeof FormSchema>;

const TYPE_VARIANT: Record<Discount["type"], "info" | "success" | "warning"> = {
  PERCENT: "info",
  FIXED: "success",
  BOGO: "warning",
};

export function DiscountsClient() {
  const t = useTranslations("promotions.discounts");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();
  const [sheet, setSheet] = React.useState<{ mode: "create" | "edit"; row?: Discount } | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<Discount | null>(null);

  const list = useQuery({
    queryKey: ["discounts"],
    queryFn: async () => {
      const data = await clientFetch<
        | { discounts?: Discount[]; data?: Discount[] }
        | Discount[]
      >({ path: "/discounts" });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw) ? raw : raw?.discounts ?? raw?.data ?? []) as Discount[];
    },
  });

  const upsert = useMutation({
    mutationFn: async (input: { id?: string; payload: Record<string, unknown> }) => {
      if (input.id) {
        return clientFetch({ path: `/discounts/${input.id}`, method: "PUT", body: input.payload });
      }
      return clientFetch({ path: "/discounts", method: "POST", body: input.payload });
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ["discounts"] });
      toast({ title: vars.id ? t("updatedToast") : t("createdToast") });
      setSheet(null);
    },
    onError: (e: Error) => {
      toast({ title: t("saveError"), description: e.message, variant: "destructive" });
    },
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/discounts/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["discounts"] });
      toast({ title: t("deletedToast") });
      setConfirmDelete(null);
    },
    onError: (e: Error) => {
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" });
    },
  });

  const items = list.data ?? [];

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={() => setSheet({ mode: "create" })}>
          <Plus className="h-4 w-4" />
          {t("newDiscount")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: items.length })}
          </span>
          {list.isFetching && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>
        {list.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {tCommon("loading")}
          </div>
        ) : list.error ? (
          <div className="p-12 text-center text-sm text-error">
            {(list.error as Error).message}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Tag className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
            <Button variant="outline" onClick={() => setSheet({ mode: "create" })}>
              <Plus className="h-4 w-4" />
              {t("newDiscount")}
            </Button>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.type")}</TableHead>
                <TableHead>{t("col.value")}</TableHead>
                <TableHead>{t("col.window")}</TableHead>
                <TableHead>{t("col.active")}</TableHead>
                <TableHead className="w-12"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((d) => (
                <TableRow key={d.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{d.name}</TableCell>
                  <TableCell>
                    <StatusBadge variant={TYPE_VARIANT[d.type] ?? "neutral"}>
                      {t(`type.${d.type}`)}
                    </StatusBadge>
                  </TableCell>
                  <TableCell className="font-mono tabular-nums">
                    {d.type === "PERCENT"
                      ? `%${d.value}`
                      : d.type === "FIXED"
                        ? formatChf(d.value)
                        : `${d.value}`}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {d.starts_at ? formatDateTime(d.starts_at) : "—"}
                    {" → "}
                    {d.ends_at ? formatDateTime(d.ends_at) : "∞"}
                  </TableCell>
                  <TableCell>
                    {d.active ? (
                      <StatusBadge variant="success" withDot>
                        {tCommon("active")}
                      </StatusBadge>
                    ) : (
                      <StatusBadge variant="neutral">
                        {tCommon("inactive")}
                      </StatusBadge>
                    )}
                  </TableCell>
                  <TableCell>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" className="h-8 w-8">
                          <MoreHorizontal className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onSelect={() => setSheet({ mode: "edit", row: d })}>
                          <Pencil className="h-4 w-4" />
                          {tCommon("edit")}
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          className="text-error"
                          onSelect={() => setConfirmDelete(d)}
                        >
                          <Trash2 className="h-4 w-4" />
                          {tCommon("delete")}
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      <DiscountForm
        open={sheet !== null}
        mode={sheet?.mode ?? "create"}
        item={sheet?.row}
        onClose={() => setSheet(null)}
        onSubmit={(input) => {
          const payload: Record<string, unknown> = {
            name: input.name,
            type: input.type,
            value: input.value,
            active: input.active,
          };
          if (input.starts_at) payload.starts_at = new Date(input.starts_at).toISOString();
          if (input.ends_at) payload.ends_at = new Date(input.ends_at).toISOString();
          upsert.mutate({ id: sheet?.row?.id, payload });
        }}
        submitting={upsert.isPending}
      />

      <AlertDialog
        open={confirmDelete !== null}
        onOpenChange={(o) => !o && setConfirmDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("deleteConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("deleteConfirmBody", { name: confirmDelete?.name ?? "" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction
              className="bg-error text-error-foreground hover:bg-error/90"
              onClick={() => confirmDelete && remove.mutate(confirmDelete.id)}
            >
              {tCommon("delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function DiscountForm({
  open,
  mode,
  item,
  onClose,
  onSubmit,
  submitting,
}: {
  open: boolean;
  mode: "create" | "edit";
  item?: Discount;
  onClose: () => void;
  onSubmit: (input: FormInput) => void;
  submitting: boolean;
}) {
  const t = useTranslations("promotions.discounts");
  const tCommon = useTranslations("common");

  const form = useForm<FormInput>({
    resolver: zodResolver(FormSchema),
    values: item
      ? {
          name: item.name,
          type: item.type,
          value: item.value,
          active: item.active,
          starts_at: item.starts_at ? item.starts_at.slice(0, 16) : "",
          ends_at: item.ends_at ? item.ends_at.slice(0, 16) : "",
        }
      : {
          name: "",
          type: "PERCENT",
          value: 10,
          active: true,
          starts_at: "",
          ends_at: "",
        },
  });

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {mode === "create" ? t("newDiscount") : t("editDiscount")}
          </DialogTitle>
          <DialogDescription>{t("formHint")}</DialogDescription>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-3 pt-2">
          <div className="space-y-1">
            <Label>{t("col.name")}</Label>
            <Input {...form.register("name")} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.type")}</Label>
              <Select
                value={form.watch("type")}
                onValueChange={(v) =>
                  form.setValue("type", v as FormInput["type"], { shouldDirty: true })
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="PERCENT">{t("type.PERCENT")}</SelectItem>
                  <SelectItem value="FIXED">{t("type.FIXED")}</SelectItem>
                  <SelectItem value="BOGO">{t("type.BOGO")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>{t("col.value")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                {...form.register("value")}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.startsAt")}</Label>
              <Input type="datetime-local" {...form.register("starts_at")} />
            </div>
            <div className="space-y-1">
              <Label>{t("col.endsAt")}</Label>
              <Input type="datetime-local" {...form.register("ends_at")} />
            </div>
          </div>
          <div className="flex items-center gap-2 pt-2">
            <Switch
              checked={form.watch("active")}
              onCheckedChange={(v) => form.setValue("active", v, { shouldDirty: true })}
            />
            <Label>{t("col.active")}</Label>
          </div>
          <DialogFooter className="pt-3">
            <Button type="button" variant="outline" onClick={onClose}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
              {tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
