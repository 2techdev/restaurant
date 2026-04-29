import { NextResponse } from "next/server";
import { setActiveTenant } from "@/lib/auth";

export async function POST(req: Request) {
  const { tenantId } = (await req.json().catch(() => ({}))) as { tenantId?: string };
  if (!tenantId) {
    return NextResponse.json({ code: "VALIDATION_ERROR", message: "tenantId required" }, { status: 400 });
  }
  await setActiveTenant(tenantId);
  return NextResponse.json({ ok: true, tenantId });
}
