# Design System: Precision POS Framework

## 1. Overview & Creative North Star
**Creative North Star: The Kinetic Monolith**
This design system rejects the cluttered, line-heavy aesthetic of traditional point-of-sale systems in favor of a "Kinetic Monolith" approach. It is an editorial-grade interface designed for high-pressure Gastronomy environments, where precision meets luxury. By utilizing deep tonal layering and high-contrast typography, we create an interface that feels carved out of a single piece of dark obsidian. 

The goal is to move away from "software" and toward "instrument." We break the standard grid through intentional asymmetry—using large, bold price displays as anchors and overlapping surface layers to guide the eye without the "prison bars" of traditional borders.

## 2. Colors & Surface Philosophy

### The "No-Line" Rule
**Borders are strictly prohibited.** To separate a sidebar from a main stage, or a card from a background, you must use color shifts. This creates a more organic, premium feel that reduces visual noise for the operator.

### Surface Hierarchy & Nesting
Depth is achieved through a "rising" scale of luminosity. As elements become more interactive or urgent, they "rise" toward the user by becoming lighter.
- **Surface (Base):** `#111319` — The foundation of the app.
- **Surface Low:** `#1A1D27` — Used for secondary sidebars or inactive containers.
- **Surface Medium:** `#222633` — The standard card level.
- **Surface High:** `#2A2F3D` — Used for active states, modals, or "pressed" interactions.

### The "Glass & Gradient" Rule
To inject "soul" into the dark UI, use the **Primary Brand Gradient** (`#AFC6FF` to `#528DFF` at 135°) exclusively for high-intent actions. For floating overlays (like a quick-add menu), utilize **Glassmorphism**: apply a 20% opacity to the Surface High token with a `20px` backdrop blur. This ensures the UI feels like a cohesive environment rather than a series of disconnected boxes.

## 3. Typography
We use **Inter** as our sole typeface to maintain a clean, architectural look. The hierarchy is designed to highlight the "Numbers that Matter."

- **Display & Headlines:** Use for total bill amounts and table numbers. 
  - *Rule:* Prices and Totals must use **Extrabold (800)** weight. This creates a clear visual anchor in a busy restaurant environment.
- **Body & Labels:** Use Regular (400) for descriptions and Medium (500) for button labels.
- **Tonal Contrast:**
    - **Primary Text (`#F0F0F5`):** Critical information only (Prices, active items).
    - **Secondary Text (`#8E8E9A`):** Modifiers, seat numbers, timestamps.
    - **Dim Text (`#5A5A6A`):** Metadata, inactive states, or placeholder hints.

## 4. Elevation & Depth

### The Layering Principle
Instead of shadows for every element, use **Tonal Stacking**. 
*Example:* A "Modifier" list inside an "Order" card. If the Order card is `Surface Medium`, the Modifier list container should be `Surface Low` (inset) or `Surface High` (raised).

### Ambient Shadows
When an element must float (e.g., a checkout drawer), use an **Ambient Shadow**:
- **Y-offset:** 8px | **Blur:** 24px | **Color:** `#000000` at 15% opacity.
- Never use harsh, tight shadows. The light source should feel broad and soft.

### The "Ghost Border" Fallback
If contrast is legally required for accessibility, use a **Ghost Border**: 1px width, `Outline Variant` token at 10% opacity. It should be felt, not seen.

## 5. Components

### Buttons
- **Primary:** Gradient (`#AFC6FF` to `#528DFF`), 12px rounding, 48px minimum height. Use white text with a subtle `0.5px` letter spacing.
- **Secondary:** Surface Medium background, Secondary Text color.
- **Success/Error/Warning:** Use solid fills of the respective Accents (Green, Red, Orange) only for high-priority status changes.

### Cards & Lists
- **The "No-Divider" Rule:** Never use lines to separate items in a list. Instead, use a **16px (Spacing Scale 4)** vertical gap. 
- **Active State:** Change the background of a list item from `Surface Low` to `Surface Medium` to indicate selection.

### POS-Specific Components
- **The Totalizer:** A large-scale footer component using `Display-LG` typography in Extrabold. This must be the highest contrast element on the screen.
- **Table Grid:** Use `Surface Low` for empty tables and `Accent Green` for occupied tables. The "Occupied" state should use a subtle glow (outer shadow of the same color at 10% opacity) to signify activity.
- **Touch Targets:** All interactive elements must maintain a minimum hit area of **48x48px** to account for high-speed tablet interaction.

## 6. Do's and Don'ts

### Do
- **Do** use asymmetrical spacing. A wider margin on the left than the right can create a sophisticated, editorial "magazine" feel.
- **Do** use the `Surface High` token for any element that the user is currently touching or dragging.
- **Do** leverage the `10-inch Tablet Landscape` optimization by placing primary navigation on the left thumb-zone and the "Total/Checkout" on the right thumb-zone.

### Don't
- **Don't** use 1px dividers to separate the header from the body. Use a shift from `Surface` to `Surface Low`.
- **Don't** use the Primary Gradient for secondary actions; it should be a "reward" for the final step of a task.
- **Don't** use high-saturation backgrounds for text containers. Keep the "ink" light and the "paper" dark and desaturated.