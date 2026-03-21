# Design System Documentation: The Precision POS Framework

## 1. Overview & Creative North Star
### Creative North Star: "The Kinetic Architect"
In the high-pressure environment of a professional kitchen or a bustling dining floor, UI must do more than just exist—it must perform. This design system moves away from the "flat app" aesthetic toward **Kinetic Architecture**. We treat the 10" tablet screen not as a canvas for buttons, but as a modular control deck defined by Swiss precision, intentional asymmetry, and deep tonal layering.

By prioritizing typographic hierarchy and shifting surfaces over traditional lines, we create an interface that feels fast, authoritative, and premium. We do not use borders to separate ideas; we use elevation and atmosphere.

---

## 2. Colors & Atmospheric Depth
Our color palette is rooted in the "Midnight Navy" spectrum, designed to reduce eye fatigue during long shifts while maintaining high-contrast "Action Zones."

### The "No-Line" Rule
**Strict Mandate:** 1px solid borders for sectioning are prohibited. 
In this design system, boundaries are defined exclusively through:
*   **Background Shifts:** Placing a `surface-container-low` (#191B22) component against a `surface` (#111319) background.
*   **Negative Space:** Using the 16px or 24px spacing units to let the eye create its own "gutters."

### Surface Hierarchy & Nesting
Treat the UI as a physical stack of materials. 
*   **Base Layer (`surface-dim` / #111319):** The "tabletop." Used for the main background.
*   **Intermediate Layer (`surface-container` / #1E1F26):** The "tray." Used for the main order entry area or sidebar.
*   **Top Layer (`surface-container-highest` / #33343B):** The "active tool." Used for modals, active product cards, or the numeric PIN pad.

### The "Glass & Gradient" Rule
To elevate the POS from a utility to a premium experience, use **Backdrop Blur (20px-40px)** on floating elements like "Total Amount" footers or top navigation bars. 
*   **Signature Texture:** Primary Action Buttons should never be flat. Apply a subtle linear gradient from `primary` (#AFC6FF) to `primary-container` (#528DFF) at a 135° angle. This adds a "machined" look that feels tactile and expensive.

---

## 3. Typography: Editorial Authority
We utilize **Inter** with tight tracking (-0.02em) to mimic the legendary Swiss International Typographic Style.

*   **Display & Headlines:** Use `display-md` (2.75rem) for hero numbers like the "Grand Total." This isn't just data; it's the most important information on the screen. Set to `Extrabold` (800).
*   **Titles:** Use `title-lg` (1.375rem) for category headers (e.g., "Starters," "Mains"). These should be `Semibold` (600) to stand out against the dark backgrounds.
*   **Body & Labels:** Use `body-md` (0.875rem) for item descriptions and `label-sm` (0.6875rem) for modifiers (e.g., "Extra Sauce"). 
*   **Functional Contrast:** Secondary labels (`text-secondary` / #8E8E9A) should always be paired with `text-primary` (#F0F0F5) to ensure a clear hierarchy of "What it is" vs. "What it costs/does."

---

## 4. Elevation & Depth
We reject the "drop shadow" of the early web. We use **Ambient Occlusion**—depth that feels like light hitting a physical surface.

*   **Tonal Layering:** To highlight an active order, don't add a border. Instead, transition the card from `surface-container-low` to `surface-bright` (#373940).
*   **Ambient Shadows:** For floating modals, use a shadow with a 48px blur, 0px offset, and 6% opacity using a tinted version of the accent color (#4F8CFF). This makes the element feel like it's glowing slightly rather than casting a dirty shadow.
*   **The "Ghost Border" Fallback:** If a layout becomes too dense and requires a separator, use the `outline-variant` (#424753) at **15% opacity**. This creates a "suggestion" of a line that disappears into the background, maintaining the "No-Line" philosophy.

---

## 5. Components
### Buttons
*   **Primary Action (Pay/Print):** Gradient fill (`primary` to `primary-container`), 12px radius, 56px height. Text: `title-sm` (Bold).
*   **Secondary (Add Modifier):** `surface-container-highest` background, no border, 48px height.
*   **Tertiary (Cancel/Clear):** Ghost style. No background. `text-dim` (#5A5A6A) typography.

### Product Cards
*   **Constraint:** Minimum 88px height.
*   **Styling:** No dividers between cards. Use a `3.5` (0.875rem) spacing gap. Use a `surface-container-low` background. On tap, animate to `surface-bright` with a 200ms ease-in-out transition.

### The "Active-State" Chip
*   Used for table status (e.g., "Dining," "Bill Requested").
*   Use a high-chroma background (`secondary_container` / #05B046) with `on_secondary_container` (#003A11) text. This high-contrast pairing ensures "Swiss-style" legibility at a glance.

### Numerical PIN Pad
*   **Precision Geometry:** Keys must be 64px height. Use `surface-container-high` (#282A30).
*   **Interactions:** Upon press, the key should scale down slightly (98%) and shift to `primary-fixed-dim` (#AFC6FF) to provide instant haptic and visual feedback.

---

## 6. Do's and Don'ts

### Do
*   **Do** use asymmetrical layouts for the main dashboard (e.g., a slim 25% sidebar for the check and a wide 75% area for products).
*   **Do** use `extrabold` for currency symbols and prices to create "Visual Anchors."
*   **Do** allow 24px of "breathing room" (Spacing 6) around the edges of the tablet screen to prevent accidental touches near the bezel.

### Don't
*   **Don't** use 100% white (#FFFFFF). It is too harsh for dark mode. Always use `text-primary` (#F0F0F5).
*   **Don't** use lines to separate list items. Use a 1px vertical offset in background color if absolutely necessary, but prioritize vertical white space.
*   **Don't** use "Standard" Android ripple effects. Use a sophisticated color-fill transition that feels like a physical light turning on.