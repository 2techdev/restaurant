import { NextResponse } from "next/server";
import { apiPost } from "@/lib/api";
import { setSessionCookies, type PartnerUser } from "@/lib/auth";

interface LoginResponse {
  access_token: string;
  expires_in: number;
  token_type: string;
  user: PartnerUser;
}

export async function POST(req: Request) {
  let body: { email?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ code: "INVALID_BODY", message: "Invalid JSON" }, { status: 400 });
  }
  if (!body.email || !body.password) {
    return NextResponse.json({ code: "VALIDATION_ERROR", message: "email & password required" }, { status: 400 });
  }
  try {
    const data = await apiPost<LoginResponse>("/partner/auth/login", {
      email: body.email,
      password: body.password,
    });
    await setSessionCookies({ token: data.access_token, user: data.user });
    return NextResponse.json({ user: data.user });
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string };
    return NextResponse.json(
      { code: err.code ?? "LOGIN_FAILED", message: err.message ?? "Login failed" },
      { status: err.status ?? 500 },
    );
  }
}
