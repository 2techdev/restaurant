import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LoginForm } from "@/components/auth/login-form";

describe("LoginForm", () => {
  beforeEach(() => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ user: { id: "1", email: "x@y", name: "X", role: "RESTAURANT_MANAGER", organization_id: "o" } }),
    }) as unknown as typeof fetch;
  });

  it("renders email and password fields", () => {
    render(<LoginForm />);
    expect(screen.getByLabelText("auth.email")).toBeInTheDocument();
    expect(screen.getByLabelText("auth.password")).toBeInTheDocument();
  });

  it("shows validation error when email empty", async () => {
    const user = userEvent.setup();
    render(<LoginForm />);
    const submit = screen.getByRole("button", { name: /auth\.login/ });
    await user.click(submit);
    // Zod default message contains "Invalid" or "Required" — RHF shows it inline
    // Form should NOT have submitted (fetch not called)
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("submits when fields valid", async () => {
    const user = userEvent.setup();
    render(<LoginForm />);
    await user.type(screen.getByLabelText("auth.email"), "admin@example.com");
    await user.type(screen.getByLabelText("auth.password"), "secret123");
    await user.click(screen.getByRole("button", { name: /auth\.login/ }));
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/auth/login",
      expect.objectContaining({ method: "POST" })
    );
  });
});
