"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, KeyRound, Ban, CheckCircle2, Trash2, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
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
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import type { AdminUserRow } from "@/lib/server-data";

const ROLE_OPTIONS = [
  { value: "admin", labelKey: "roleAdmin" },
  { value: "brand_manager", labelKey: "roleBrandManager" },
  { value: "store_manager", labelKey: "roleStoreManager" },
  { value: "viewer", labelKey: "roleViewer" },
] as const;

interface CreatedCredential {
  email: string;
  password: string;
  name: string;
}

export function UsersClient({
  initial,
  canWrite,
  currentUserId,
}: {
  initial: AdminUserRow[];
  canWrite: boolean;
  currentUserId: string;
}) {
  const t = useTranslations("users");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const [search, setSearch] = React.useState("");
  const [roleFilter, setRoleFilter] = React.useState<string>("all");
  const [statusFilter, setStatusFilter] = React.useState<string>("all");

  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<AdminUserRow | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<AdminUserRow | null>(null);
  const [credential, setCredential] = React.useState<CreatedCredential | null>(null);

  const { data: users = initial } = useQuery({
    queryKey: ["admin-users"],
    queryFn: async () => {
      const r = await clientFetch<{ data: AdminUserRow[] }>({ path: "/admin/users" });
      return r?.data ?? [];
    },
    initialData: initial,
  });

  const filtered = React.useMemo(() => {
    const q = search.trim().toLowerCase();
    return (users ?? []).filter((u) => {
      if (q && !u.email.toLowerCase().includes(q) && !u.name.toLowerCase().includes(q)) return false;
      if (roleFilter !== "all" && u.role !== roleFilter) return false;
      if (statusFilter !== "all" && u.status !== statusFilter) return false;
      return true;
    });
  }, [users, search, roleFilter, statusFilter]);

  const refresh = () => qc.invalidateQueries({ queryKey: ["admin-users"] });

  const disableMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/admin/users/${id}/disable`, method: "PUT" }),
    onSuccess: () => {
      toast({ title: t("disableSuccess") });
      refresh();
    },
    onError: (e: Error) => toast({ title: t("disableError"), description: e.message, variant: "destructive" }),
  });
  const enableMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/admin/users/${id}/enable`, method: "PUT" }),
    onSuccess: () => {
      toast({ title: t("enableSuccess") });
      refresh();
    },
    onError: (e: Error) => toast({ title: t("enableError"), description: e.message, variant: "destructive" }),
  });
  const resetMut = useMutation<{ generated_password: string }, Error, AdminUserRow>({
    mutationFn: (u: AdminUserRow) =>
      clientFetch<{ generated_password: string }>({
        path: `/admin/users/${u.id}/reset-password`,
        method: "PUT",
      }),
    onSuccess: (data, u) => {
      setCredential({ email: u.email, password: data.generated_password, name: u.name });
      refresh();
    },
    onError: (e: Error) => toast({ title: t("resetError"), description: e.message, variant: "destructive" }),
  });
  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/admin/users/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: t("deleteSuccess") });
      refresh();
      setConfirmDelete(null);
    },
    onError: (e: Error) => toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-end justify-between">
        <div className="flex flex-wrap gap-2 items-end">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder={t("searchPlaceholder")}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-8 w-64"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">{t("filterRole")}</Label>
            <Select value={roleFilter} onValueChange={setRoleFilter}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                {ROLE_OPTIONS.map((r) => (
                  <SelectItem key={r.value} value={r.value}>{t(r.labelKey)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">{t("filterStatus")}</Label>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                <SelectItem value="active">{t("statusActive")}</SelectItem>
                <SelectItem value="disabled">{t("statusDisabled")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        {canWrite && (
          <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
            <Plus className="h-4 w-4" />
            {t("addUser")}
          </Button>
        )}
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colEmail")}</TableHead>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colRole")}</TableHead>
              <TableHead>{t("colStatus")}</TableHead>
              <TableHead>{t("colLastLogin")}</TableHead>
              {canWrite && <TableHead className="text-right">{t("colActions")}</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 && (
              <TableRow>
                <TableCell colSpan={canWrite ? 6 : 5} className="text-center text-muted-foreground py-8">
                  {t("emptyState")}
                </TableCell>
              </TableRow>
            )}
            {filtered.map((u) => {
              const isMe = u.id === currentUserId;
              return (
                <TableRow key={u.id}>
                  <TableCell className="font-medium">
                    {u.email}
                    {isMe && <Badge variant="secondary" className="ml-2 text-xs">{t("you")}</Badge>}
                  </TableCell>
                  <TableCell>{u.name}</TableCell>
                  <TableCell><RoleBadge role={u.role} /></TableCell>
                  <TableCell><StatusBadge status={u.status} /></TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {u.last_login_at ? new Date(u.last_login_at).toLocaleString() : "—"}
                  </TableCell>
                  {canWrite && (
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={t("editAction")}
                          title={t("editAction")}
                          onClick={() => { setEditing(u); setFormOpen(true); }}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={t("resetPasswordAction")}
                          title={t("resetPasswordAction")}
                          onClick={() => resetMut.mutate(u)}
                          disabled={resetMut.isPending}
                        >
                          <KeyRound className="h-4 w-4" />
                        </Button>
                        {u.status === "active" ? (
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={t("disableAction")}
                            title={t("disableAction")}
                            onClick={() => disableMut.mutate(u.id)}
                            disabled={isMe || disableMut.isPending}
                          >
                            <Ban className="h-4 w-4" />
                          </Button>
                        ) : (
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={t("enableAction")}
                            title={t("enableAction")}
                            onClick={() => enableMut.mutate(u.id)}
                            disabled={enableMut.isPending}
                          >
                            <CheckCircle2 className="h-4 w-4" />
                          </Button>
                        )}
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={t("deleteAction")}
                          title={t("deleteAction")}
                          onClick={() => setConfirmDelete(u)}
                          disabled={isMe}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      <UserFormDialog
        open={formOpen}
        onOpenChange={setFormOpen}
        initial={editing}
        onSaved={(cred) => {
          setFormOpen(false);
          refresh();
          if (cred) setCredential(cred);
        }}
      />

      <AlertDialog open={!!confirmDelete} onOpenChange={(open) => !open && setConfirmDelete(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("deleteConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("deleteConfirmBody", { email: confirmDelete?.email ?? "" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => confirmDelete && deleteMut.mutate(confirmDelete.id)}
              disabled={deleteMut.isPending}
            >
              {tCommon("delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <CredentialDialog
        credential={credential}
        onClose={() => setCredential(null)}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Form dialog (create + edit)
// ---------------------------------------------------------------------------

function UserFormDialog({
  open,
  onOpenChange,
  initial,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: AdminUserRow | null;
  onSaved: (credential: CreatedCredential | null) => void;
}) {
  const t = useTranslations("users");
  const tCommon = useTranslations("common");
  const { toast } = useToast();

  const [email, setEmail] = React.useState("");
  const [name, setName] = React.useState("");
  const [role, setRole] = React.useState("admin");
  const [autoGenerate, setAutoGenerate] = React.useState(true);
  const [password, setPassword] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) {
      if (initial) {
        setEmail(initial.email);
        setName(initial.name);
        setRole(initial.role);
      } else {
        setEmail("");
        setName("");
        setRole("admin");
      }
      setAutoGenerate(true);
      setPassword("");
    }
  }, [open, initial]);

  const isEdit = !!initial;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      if (isEdit && initial) {
        await clientFetch({
          path: `/admin/users/${initial.id}`,
          method: "PUT",
          body: { name, role },
        });
        toast({ title: t("updateSuccess") });
        onSaved(null);
      } else {
        const body: Record<string, unknown> = { email, name, role };
        if (!autoGenerate && password) body.password = password;
        const res = await clientFetch<{
          user: AdminUserRow;
          generated_password?: string;
        }>({ path: "/admin/users", method: "POST", body });
        const cred = res.generated_password
          ? { email: res.user.email, password: res.generated_password, name: res.user.name }
          : null;
        onSaved(cred);
      }
    } catch (err) {
      toast({
        title: t("saveError"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{isEdit ? t("editUser") : t("addUser")}</DialogTitle>
            <DialogDescription>
              {isEdit ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1">
              <Label htmlFor="email">{t("colEmail")}</Label>
              <Input
                id="email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={isEdit}
                autoComplete="email"
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="name">{t("colName")}</Label>
              <Input
                id="name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="role">{t("colRole")}</Label>
              <Select value={role} onValueChange={setRole}>
                <SelectTrigger id="role"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ROLE_OPTIONS.map((r) => (
                    <SelectItem key={r.value} value={r.value}>{t(r.labelKey)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {!isEdit && (
              <div className="space-y-2 rounded-md border p-3">
                <div className="flex items-center gap-2">
                  <input
                    id="auto"
                    type="checkbox"
                    checked={autoGenerate}
                    onChange={(e) => setAutoGenerate(e.target.checked)}
                    className="h-4 w-4"
                  />
                  <Label htmlFor="auto" className="font-normal cursor-pointer">
                    {t("autoGenerate")}
                  </Label>
                </div>
                {!autoGenerate && (
                  <Input
                    type="text"
                    placeholder={t("manualPassword")}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    minLength={6}
                  />
                )}
              </div>
            )}
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Credential reveal dialog (one-shot password display)
// ---------------------------------------------------------------------------

function CredentialDialog({
  credential,
  onClose,
}: {
  credential: CreatedCredential | null;
  onClose: () => void;
}) {
  const t = useTranslations("users");
  const tCommon = useTranslations("common");
  const [copied, setCopied] = React.useState(false);
  const text = credential ? `${credential.email} / ${credential.password}` : "";
  const copy = () => {
    if (!text) return;
    navigator.clipboard?.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2_000);
  };
  return (
    <Dialog open={!!credential} onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("credentialTitle")}</DialogTitle>
          <DialogDescription>{t("credentialSubtitle")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
            {credential?.email}
          </div>
          <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
            {credential?.password}
          </div>
          <p className="text-xs text-muted-foreground">{t("credentialWarning")}</p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={copy}>{copied ? tCommon("success") : t("copyAction")}</Button>
          <Button onClick={onClose}>{tCommon("confirm")}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

function RoleBadge({ role }: { role: string }) {
  const t = useTranslations("users");
  const map: Record<string, { variant: "default" | "secondary" | "outline"; label: string }> = {
    admin: { variant: "default", label: t("roleAdmin") },
    brand_manager: { variant: "secondary", label: t("roleBrandManager") },
    store_manager: { variant: "outline", label: t("roleStoreManager") },
    viewer: { variant: "outline", label: t("roleViewer") },
  };
  const m = map[role] ?? { variant: "outline" as const, label: role };
  return <Badge variant={m.variant}>{m.label}</Badge>;
}

function StatusBadge({ status }: { status: string }) {
  const t = useTranslations("users");
  const isActive = status === "active";
  return (
    <Badge variant={isActive ? "default" : "secondary"} className={isActive ? "bg-emerald-500/15 text-emerald-700 hover:bg-emerald-500/20 border-emerald-500/30" : ""}>
      {isActive ? t("statusActive") : t("statusDisabled")}
    </Badge>
  );
}
