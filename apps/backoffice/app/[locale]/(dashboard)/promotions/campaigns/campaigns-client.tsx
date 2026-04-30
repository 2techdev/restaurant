"use client";

/**
 * Campaigns (Agent A backend — /api/v1/campaigns CRUD).
 * description + time window + channel chips (email|sms|app).
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
  Megaphone,
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
import { formatDateTime } from "@/lib/utils";

interface Campaign {
  id: string;
  tenant_id: string;
  name: string;
  description?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  active: boolean;
  channels?: string[] | null;
}

const CHANNELS = ["email", "sms", "app"] as const;

const FormSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  starts_at: z.string().optional(),
  ends_at: z.string().optional(),
  active: z.boolean(),
  channels: z.array(z.string()).default([]),
});
type FormInput = z.infer<typeof FormSchema>;

export function CampaignsClient() {
  const t = useTranslations("promotions.campaigns");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();
  const [sheet, setSheet] = React.useState<{ mode: "create" | "edit"; row?: Campaign } | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<Campaign | null>(null);

  const list = useQuery({
    queryKey: ["campaigns"],
    queryFn: async () => {
      const data = await clientFetch<
        | { campaigns?: Campaign[]; data?: Campaign[] }
        | Campaign[]
      >({ path: "/campaigns" });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw) ? raw : raw?.campaigns ?? raw?.data ?? []) as Campaign[];
    },
  });

  const upsert = useMutation({
    mutationFn: async (input: { id?: string; payload: Record<string, unknown> }) => {
      if (input.id) {
        return clientFetch({ path: `/campaigns/${input.id}`, method: "PUT", body: input.payload });
      }
      return clientFetch({ path: "/campaigns", method: "POST", body: input.payload });
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ["campaigns"] });
      toast({ title: vars.id ? t("updatedToast") : t("createdToast") });
      setSheet(null);
    },
    onError: (e: Error) => {
      toast({ title: t("saveError"), description: e.message, variant: "destructive" });
    },
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/campaigns/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["campaigns"] });
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
          {t("newCampaign")}
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
            <Megaphone className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
            <Button variant="outline" onClick={() => setSheet({ mode: "create" })}>
              <Plus className="h-4 w-4" />
              {t("newCampaign")}
            </Button>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.description")}</TableHead>
                <TableHead>{t("col.window")}</TableHead>
                <TableHead>{t("col.channels")}</TableHead>
                <TableHead>{t("col.active")}</TableHead>
                <TableHead className="w-12"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((c) => (
                <TableRow key={c.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{c.name}</TableCell>
                  <TableCell className="text-muted-foreground max-w-[280px] truncate">
                    {c.description ?? "—"}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {c.starts_at ? formatDateTime(c.starts_at) : "—"}
                    {" → "}
                    {c.ends_at ? formatDateTime(c.ends_at) : "∞"}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {(c.channels ?? []).map((ch) => (
                        <StatusBadge key={ch} variant="info">
                          {t(`channel.${ch}`)}
                        </StatusBadge>
                      ))}
                      {(!c.channels || c.channels.length === 0) && (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    {c.active ? (
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
                        <DropdownMenuItem onSelect={() => setSheet({ mode: "edit", row: c })}>
                          <Pencil className="h-4 w-4" />
                          {tCommon("edit")}
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          className="text-error"
                          onSelect={() => setConfirmDelete(c)}
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

      <CampaignForm
        open={sheet !== null}
        mode={sheet?.mode ?? "create"}
        item={sheet?.row}
        onClose={() => setSheet(null)}
        onSubmit={(input) => {
          const payload: Record<string, unknown> = {
            name: input.name,
            description: input.description ?? null,
            active: input.active,
            channels: input.channels,
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

function CampaignForm({
  open,
  mode,
  item,
  onClose,
  onSubmit,
  submitting,
}: {
  open: boolean;
  mode: "create" | "edit";
  item?: Campaign;
  onClose: () => void;
  onSubmit: (input: FormInput) => void;
  submitting: boolean;
}) {
  const t = useTranslations("promotions.campaigns");
  const tCommon = useTranslations("common");

  const form = useForm<FormInput>({
    resolver: zodResolver(FormSchema),
    values: item
      ? {
          name: item.name,
          description: item.description ?? "",
          starts_at: item.starts_at ? item.starts_at.slice(0, 16) : "",
          ends_at: item.ends_at ? item.ends_at.slice(0, 16) : "",
          active: item.active,
          channels: item.channels ?? [],
        }
      : {
          name: "",
          description: "",
          starts_at: "",
          ends_at: "",
          active: true,
          channels: [],
        },
  });

  const channels = form.watch("channels") ?? [];
  const toggleChannel = (c: string) => {
    const next = channels.includes(c) ? channels.filter((x) => x !== c) : [...channels, c];
    form.setValue("channels", next, { shouldDirty: true });
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {mode === "create" ? t("newCampaign") : t("editCampaign")}
          </DialogTitle>
          <DialogDescription>{t("formHint")}</DialogDescription>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-3 pt-2">
          <div className="space-y-1">
            <Label>{t("col.name")}</Label>
            <Input {...form.register("name")} />
          </div>
          <div className="space-y-1">
            <Label>{t("col.description")}</Label>
            <textarea
              rows={2}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              {...form.register("description")}
            />
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
          <div className="space-y-1">
            <Label>{t("col.channels")}</Label>
            <div className="flex flex-wrap gap-2">
              {CHANNELS.map((c) => {
                const on = channels.includes(c);
                return (
                  <button
                    key={c}
                    type="button"
                    onClick={() => toggleChannel(c)}
                    className={`px-3 py-1 rounded-full text-xs border transition-colors ${
                      on
                        ? "bg-info-soft text-info border-info/30"
                        : "bg-muted/40 text-muted-foreground border-border hover:bg-muted"
                    }`}
                  >
                    {t(`channel.${c}`)}
                  </button>
                );
              })}
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
