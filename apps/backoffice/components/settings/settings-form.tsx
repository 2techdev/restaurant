"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { localeNames, locales } from "@/lib/i18n/config";

const TIMEZONES = [
  "Europe/Zurich",
  "Europe/Berlin",
  "Europe/Vienna",
  "Europe/Istanbul",
  "Europe/Paris",
  "Europe/Rome",
];

export function SettingsForm() {
  const t = useTranslations("settings");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [tz, setTz] = React.useState("Europe/Zurich");
  const [lang, setLang] = React.useState<string>("tr");
  const [name, setName] = React.useState("");

  const onSave = (e: React.FormEvent) => {
    e.preventDefault();
    // Backend settings endpoint pilot v1'de henüz tam değil — UI side persist et placeholder.
    toast({ title: tCommon("success") });
  };

  return (
    <form onSubmit={onSave} className="space-y-4">
      <div className="space-y-1.5">
        <Label>{t("businessInfo")}</Label>
        <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Restoran adı" />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label>{t("timezone")}</Label>
          <Select value={tz} onValueChange={setTz}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {TIMEZONES.map((z) => <SelectItem key={z} value={z}>{z}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label>{t("defaultLanguage")}</Label>
          <Select value={lang} onValueChange={setLang}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {locales.map((l) => <SelectItem key={l} value={l}>{localeNames[l]}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      </div>
      <div className="flex justify-end">
        <Button type="submit">{tCommon("save")}</Button>
      </div>
    </form>
  );
}
