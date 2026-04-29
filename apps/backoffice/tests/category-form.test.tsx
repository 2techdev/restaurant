import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CategoryForm } from "@/components/menu/category-form";

describe("CategoryForm", () => {
  it("renders required name input", () => {
    render(<CategoryForm onSubmit={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByLabelText("menu.name")).toBeInTheDocument();
  });

  it("calls onSubmit with provided name", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    const user = userEvent.setup();
    render(<CategoryForm onSubmit={onSubmit} onCancel={vi.fn()} />);
    await user.type(screen.getByLabelText("menu.name"), "Pizza");
    await user.click(screen.getByRole("button", { name: /common\.save/ }));
    expect(onSubmit).toHaveBeenCalled();
    const call = onSubmit.mock.calls[0][0];
    expect(call.name).toBe("Pizza");
    expect(call.is_active).toBe(true);
  });

  it("Cancel button triggers onCancel", async () => {
    const onCancel = vi.fn();
    const user = userEvent.setup();
    render(<CategoryForm onSubmit={vi.fn()} onCancel={onCancel} />);
    await user.click(screen.getByRole("button", { name: /common\.cancel/ }));
    expect(onCancel).toHaveBeenCalled();
  });
});
