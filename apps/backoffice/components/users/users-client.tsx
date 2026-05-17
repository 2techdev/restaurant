"use client";

/**
 * Unified Users page — two tabs:
 *
 *   Tab 1: "Yönetim Kullanıcıları" → admin_users via /admin/users
 *          Backoffice login accounts (HQ admin, brand manager, store manager, viewer).
 *
 *   Tab 2: "POS Personeli"        → app_users via /users
 *          Restaurant staff that log into the Flutter POS/Waiter/KDS apps —
 *          email+password or a 4-6 digit PIN for fast switch on a shared tablet.
 *
 * Replaces the short-lived stand-alone "Ekip / Team" page; everything lives
 * under one sidebar entry so operators don't have to learn two pages that do
 * the same thing.
 */

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
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
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
import type { AdminUserRow, AppUserRow } from "@/lib/server-data";

const ADMIN_ROLE_OPTIONS = [
  { value: "admin", labelKey: "roleAdmin" },
  { value: "brand_manager", labelKey: "roleBrandManager" },
  { value: "store_manager", labelKey: "roleStoreManager" },
  { value: "viewer", labelKey: "roleViewer" },
] as const;

const STAFF_ROLE_OPTIONS = [
  { value: "manager", labelKey: "roleManager" },
  { value: "cashier", labelKey: "roleCashier" },
  { value: "waiter", labelKey: "roleWaiter" },
  { value: "kitchen", labelKey: "roleKitchen" },
  { value: "kiosk", labelKey: "roleKiosk" },
] as const;

interface CreatedAdminCredential {
  email: string;
  password: string;
  name: string;
}

interface CreatedStaffCredential {
  email?: string;
  password?: string;
  pin?: string;
  name: string;
}

export function UsersClient({
  initialAdmins,
  initialStaff,
  canWrite,
  currentUserId,
}: {
  initialAdmins: AdminUserRow[];
  initialStaff: AppUserRow[];
  canWrite: boolean;
  currentUserId: string;
}) {
  const t = useTranslations("users");

  return (
    <Tabs defaultValue="admin" className="space-y-4">
      <TabsList>
        <TabsTrigger value="admin">{t("tabAdmin")}</TabsTrigger>
        <TabsTrigger value="staff">{t("tabStaff")}</TabsTrigger>
      </TabsList>
      <TabsContent value="admin" className="space-y-4">
        <AdminUsersPanel
          initial={initialAdmins}
          canWrite={canWrite}
          currentUserId={currentUserId}
        />
      </TabsContent>
      <TabsContent value="staff" className="space-y-4">
        <StaffUsersPanel initial={initialStaff} canWrite={canWrite} currentUserId={currentUserId} />
      </TabsContent>
    </Tabs>
  );
}

// ===========================================================================
// Admin users panel (backoffice login)
// ===========================================================================

function AdminUsersPanel({
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
  const [credential, setCredential] = React.useState<CreatedAdminCredential | null>(null);

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
                {ADMIN_ROLE_OPTIONS.map((r) => (
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
                  <TableCell><AdminRoleBadge role={u.role} /></TableCell>
                  <TableCell><StatusBadge active={u.status === "active"} /></TableCell>
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

      <AdminUserFormDialog
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

      <AdminCredentialDialog credential={credential} onClose={() => setCredential(null)} />
    </div>
  );
}

function AdminUserFormDialog({
  open,
  onOpenChange,
  initial,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: AdminUserRow | null;
  onSaved: (credential: CreatedAdminCredential | null) => void;
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
                  {ADMIN_ROLE_OPTIONS.map((r) => (
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

function AdminCredentialDialog({
  credential,
  onClose,
}: {
  credential: CreatedAdminCredential | null;
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

// ===========================================================================
// Staff users panel (POS / Waiter / KDS login)
// ===========================================================================

function genReadablePassword(n = 12): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  const arr = new Uint8Array(n);
  crypto.getRandomValues(arr);
  let out = "";
  for (let i = 0; i < n; i++) out += alphabet[arr[i] % alphabet.length];
  return out;
}

function StaffUsersPanel({
  initial,
  canWrite,
  currentUserId,
}: {
  initial: AppUserRow[];
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
  const [editing, setEditing] = React.useState<AppUserRow | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<AppUserRow | null>(null);
  const [credential, setCredential] = React.useState<CreatedStaffCredential | null>(null);

  const { data: users = initial } = useQuery({
    queryKey: ["app-users"],
    queryFn: async () => {
      const r = await clientFetch<AppUserRow[] | { data: AppUserRow[] }>({ path: "/users" });
      if (Array.isArray(r)) return r;
      return r?.data ?? [];
    },
    initialData: initial,
  });

  const filtered = React.useMemo(() => {
    const q = search.trim().toLowerCase();
    return (users ?? []).filter((u) => {
      const hay = `${u.name ?? ""} ${u.email ?? ""}`.toLowerCase();
      if (q && !hay.includes(q)) return false;
      if (roleFilter !== "all" && u.role !== roleFilter) return false;
      if (statusFilter !== "all") {
        const wantActive = statusFilter === "active";
        if (u.is_active !== wantActive) return false;
      }
      return true;
    });
  }, [users, search, roleFilter, statusFilter]);

  const refresh = () => qc.invalidateQueries({ queryKey: ["app-users"] });

  const disableMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/users/${id}`, method: "PUT", body: { is_active: false } }),
    onSuccess: () => {
      toast({ title: t("disableSuccess") });
      refresh();
    },
    onError: (e: Error) => toast({ title: t("disableError"), description: e.message, variant: "destructive" }),
  });
  const enableMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/users/${id}`, method: "PUT", body: { is_active: true } }),
    onSuccess: () => {
      toast({ title: t("enableSuccess") });
      refresh();
    },
    onError: (e: Error) => toast({ title: t("enableError"), description: e.message, variant: "destructive" }),
  });
  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/users/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: t("deleteSuccess") });
      refresh();
      setConfirmDelete(null);
    },
    onError: (e: Error) => toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">{t("staffSubtitle")}</p>
      <div className="flex flex-wrap gap-2 items-end justify-between">
        <div className="flex flex-wrap gap-2 items-end">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder={t("staffSearchPlaceholder")}
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
                {STAFF_ROLE_OPTIONS.map((r) => (
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
            {t("addStaff")}
          </Button>
        )}
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colEmail")}</TableHead>
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
                  {t("staffEmptyState")}
                </TableCell>
              </TableRow>
            )}
            {filtered.map((u) => {
              const isMe = u.id === currentUserId;
              const lastLogin = u.last_login_at ?? u.last_login;
              return (
                <TableRow key={u.id}>
                  <TableCell className="font-medium">
                    {u.name || "—"}
                    {isMe && <Badge variant="secondary" className="ml-2 text-xs">{t("you")}</Badge>}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">{u.email ?? "—"}</TableCell>
                  <TableCell><StaffRoleBadge role={u.role} /></TableCell>
                  <TableCell><StatusBadge active={u.is_active} /></TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {lastLogin ? new Date(lastLogin).toLocaleString() : "—"}
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
                          aria-label={t("resetPinAction")}
                          title={t("resetPinAction")}
                          onClick={() => { setEditing(u); setFormOpen(true); }}
                        >
                          <KeyRound className="h-4 w-4" />
                        </Button>
                        {u.is_active ? (
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

      <StaffFormDialog
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
              {t("deleteConfirmBody", { email: confirmDelete?.name ?? "" })}
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

      <StaffCredentialDialog credential={credential} onClose={() => setCredential(null)} />
    </div>
  );
}

function StaffFormDialog({
  open,
  onOpenChange,
  initial,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: AppUserRow | null;
  onSaved: (credential: CreatedStaffCredential | null) => void;
}) {
  const t = useTranslations("users");
  const tCommon = useTranslations("common");
  const { toast } = useToast();

  const [name, setName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [role, setRole] = React.useState("waiter");
  const [autoGenerate, setAutoGenerate] = React.useState(true);
  const [password, setPassword] = React.useState("");
  const [pin, setPin] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) {
      if (initial) {
        setName(initial.name ?? "");
        setEmail(initial.email ?? "");
        setRole(initial.role || "waiter");
      } else {
        setName("");
        setEmail("");
        setRole("waiter");
      }
      setAutoGenerate(true);
      setPassword("");
      setPin("");
    }
  }, [open, initial]);

  const isEdit = !!initial;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      if (isEdit && initial) {
        const body: Record<string, unknown> = { name, role };
        if (email !== (initial.email ?? "")) body.email = email || null;
        if (password) body.password = password;
        if (pin) body.pin = pin;
        await clientFetch({ path: `/users/${initial.id}`, method: "PUT", body });
        toast({ title: t("updateSuccess") });
        if (password || pin) {
          onSaved({
            email: email || initial.email || "",
            password: password || undefined,
            pin: pin || undefined,
            name,
          });
        } else {
          onSaved(null);
        }
      } else {
        const finalPassword = autoGenerate ? genReadablePassword(12) : password;
        const body: Record<string, unknown> = {
          name,
          role,
          password: finalPassword,
        };
        if (email) body.email = email;
        if (pin) body.pin = pin;
        await clientFetch<AppUserRow>({ path: "/users", method: "POST", body });
        onSaved({
          email: email || undefined,
          password: finalPassword,
          pin: pin || undefined,
          name,
        });
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
            <DialogTitle>{isEdit ? t("editStaff") : t("addStaff")}</DialogTitle>
            <DialogDescription>
              {isEdit ? t("editStaffSubtitle") : t("addStaffSubtitle")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1">
              <Label htmlFor="s-name">{t("colName")}</Label>
              <Input
                id="s-name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="s-email">{t("colEmail")}</Label>
              <Input
                id="s-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                placeholder={t("staffEmailPlaceholder")}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="s-role">{t("colRole")}</Label>
              <Select value={role} onValueChange={setRole}>
                <SelectTrigger id="s-role"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {STAFF_ROLE_OPTIONS.map((r) => (
                    <SelectItem key={r.value} value={r.value}>{t(r.labelKey)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2 rounded-md border p-3">
              <div className="flex items-center gap-2">
                <input
                  id="s-auto"
                  type="checkbox"
                  checked={autoGenerate}
                  onChange={(e) => setAutoGenerate(e.target.checked)}
                  className="h-4 w-4"
                />
                <Label htmlFor="s-auto" className="font-normal cursor-pointer">
                  {isEdit ? t("setNewPassword") : t("autoGenerate")}
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

            <div className="space-y-1">
              <Label htmlFor="s-pin">{t("pinLabel")}</Label>
              <Input
                id="s-pin"
                type="text"
                inputMode="numeric"
                pattern="[0-9]{4,6}"
                maxLength={6}
                placeholder={isEdit ? t("pinPlaceholderEdit") : t("pinPlaceholder")}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
              />
              <p className="text-xs text-muted-foreground">{t("pinHint")}</p>
            </div>
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

function StaffCredentialDialog({
  credential,
  onClose,
}: {
  credential: CreatedStaffCredential | null;
  onClose: () => void;
}) {
  const t = useTranslations("users");
  const tCommon = useTranslations("common");
  const [copied, setCopied] = React.useState(false);
  const text = credential
    ? [
        credential.email ? `email: ${credential.email}` : null,
        credential.password ? `pw: ${credential.password}` : null,
        credential.pin ? `pin: ${credential.pin}` : null,
      ]
        .filter(Boolean)
        .join("\n")
    : "";
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
          {credential?.email ? (
            <div>
              <div className="text-xs text-muted-foreground mb-1">{t("colEmail")}</div>
              <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
                {credential.email}
              </div>
            </div>
          ) : null}
          {credential?.password ? (
            <div>
              <div className="text-xs text-muted-foreground mb-1">{t("passwordLabel")}</div>
              <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
                {credential.password}
              </div>
            </div>
          ) : null}
          {credential?.pin ? (
            <div>
              <div className="text-xs text-muted-foreground mb-1">{t("pinLabel")}</div>
              <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm tracking-widest">
                {credential.pin}
              </div>
            </div>
          ) : null}
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

// ===========================================================================
// Display helpers
// ===========================================================================

function AdminRoleBadge({ role }: { role: string }) {
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

function StaffRoleBadge({ role }: { role: string }) {
  const t = useTranslations("users");
  const map: Record<string, { variant: "default" | "secondary" | "outline"; labelKey: string }> = {
    manager:       { variant: "default",   labelKey: "roleManager" },
    store_manager: { variant: "default",   labelKey: "roleManager" },
    owner:         { variant: "default",   labelKey: "roleManager" },
    cashier:       { variant: "secondary", labelKey: "roleCashier" },
    waiter:        { variant: "outline",   labelKey: "roleWaiter" },
    kitchen:       { variant: "outline",   labelKey: "roleKitchen" },
    kds:           { variant: "outline",   labelKey: "roleKitchen" },
    kiosk:         { variant: "outline",   labelKey: "roleKiosk" },
  };
  const m = map[role];
  return <Badge variant={m?.variant ?? "outline"}>{m ? t(m.labelKey) : role}</Badge>;
}

function StatusBadge({ active }: { active: boolean }) {
  const t = useTranslations("users");
  return (
    <Badge
      variant={active ? "default" : "secondary"}
      className={active ? "bg-emerald-500/15 text-emerald-700 hover:bg-emerald-500/20 border-emerald-500/30" : ""}
    >
      {active ? t("statusActive") : t("statusDisabled")}
    </Badge>
  );
}
