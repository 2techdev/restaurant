# GastroCore POS - UI/UX Design Brief for Stitch

## Project Overview
Restaurant POS system for Android tablets (10" primary). Dark theme, touch-optimized, offline-first.
Target: Swiss and German restaurants - modern, clean, fast.

---

## Design System Specifications

### Colors
| Token | Hex | Usage |
|-------|-----|-------|
| bg-primary | #0f1117 | Main background |
| bg-secondary | #1a1d27 | Panels, sidebars |
| bg-card | #222633 | Cards, buttons |
| bg-card-hover | #2a2f3d | Hover state |
| bg-input | #181b24 | Input fields |
| accent (blue) | #4f8cff | Primary actions, links, selection |
| green | #34c759 | Success, available, payment complete |
| orange | #ff9500 | Warning, kitchen, pending |
| red | #ff3b30 | Error, occupied, void, urgent |
| yellow | #ffd60a | Notes, alerts |
| purple | #af52de | Special, VIP |
| text-primary | #f0f0f5 | Main text |
| text-secondary | #8e8e9a | Labels, descriptions |
| text-dim | #5a5a6a | Placeholder, disabled |
| border | #2a2d3a | Borders, dividers |

### Typography
- Font: Inter or SF Pro (system default on Android: Roboto)
- Sizes: 10px (badge), 11px (caption), 13px (body), 14px (body-lg), 16px (subtitle), 18px (title), 20px (heading), 24px (display), 32px+ (hero numbers)
- Weights: 400 (regular), 500 (medium), 600 (semibold), 700 (bold), 800 (extrabold)

### Spacing
- Base unit: 4px
- Component padding: 8, 12, 16, 20, 24px
- Section gaps: 12, 16, 24, 32px
- Border radius: 8px (small), 12px (medium), 16px (large), 50% (circle)

### Touch Targets
- Minimum: 44x44px (Apple HIG)
- Recommended: 48x48px+
- Product cards: min 88px height
- PIN keys: 64px height
- Action buttons: 48-56px height

### Device
- Primary: 10.1" Android tablet (1280x800 landscape)
- Secondary: 8" tablet (1280x800)
- KDS: 10" tablet (can be portrait or landscape)
- Kiosk: 15.6" touch (future)

---

## Screen List - What Stitch Needs to Design

### PHASE 1: MVP-0 Core Screens (Priority: HIGH)

---

#### S01: PIN Login Screen
**Purpose:** Staff logs in with PIN code. Fast switch between users.
**Layout:** Centered, single focus area
**Elements:**
- App logo top center: "GastroCore" (Gastro=white, Core=accent blue)
- Subtitle: "Restaurant POS System"
- User avatar row: horizontal scrollable list of staff (circle avatar with initials + name below)
  - Selected user: blue border highlight
  - Avatar colors: each user has unique color
- PIN display: 4-6 dots, filled dots = entered digits
- PIN keypad: 3x4 grid (1-9, backspace, 0, enter)
  - Enter key: accent blue
  - Backspace: red text
- Error state: dots shake + red flash on wrong PIN
- Offline indicator: small badge top-right "Offline" (orange)

---

#### S02: Shift Opening Screen
**Purpose:** Cashier opens shift by entering starting cash amount.
**Layout:** Centered card
**Elements:**
- Icon: cash drawer icon
- Title: "Vardiya Ac" / "Open Shift"
- Date/time + user name display
- Cash amount input: large number input (centered, big font)
  - Currency label below: "CHF" or "EUR"
- Numpad below input (optional, can use on-screen keyboard)
- "Start Shift" primary button (blue)
- Back button to return to login

---

#### S03: Main POS / Sales Screen ⭐ (MOST IMPORTANT)
**Purpose:** THE primary work screen. Staff spends 90% of time here.
**Layout:** 3-column layout (landscape tablet)
- Left: Category sidebar (narrow, ~90px)
- Center: Product grid (flexible width)
- Right: Order panel (fixed, ~340px)

**Top Bar (56px height, full width):**
- Left: App logo (small)
- Divider
- Online/Offline badge (green dot + "Online" or orange dot + "Offline")
- Shift number: "Shift #0047"
- Spacer
- Button: "Tables" (navigate to floor plan)
- Button: "Kitchen" (navigate to KDS)
- Button: "Shift" (shift management)
- Divider
- User avatar (small circle) + name

**Left Column - Categories (~90px):**
- Vertical list of category buttons
- Each: icon (emoji or custom) + name below
- Active state: blue border + blue tint background
- Scrollable vertically if many categories
- Categories: Populer, Ana Yemek, Pizza, Salata, Burger, Makarna, Tatli, Icecek, Sarap, Sicak Icecek

**Center Column - Products:**
- Search bar at top: magnifier icon + placeholder "Urun ara..."
- Product grid: 4 columns, scrollable
- Each product card (min 88px height):
  - Product name (semibold, 13px)
  - Price (bold, 15px, accent blue)
  - Optional: green dot (in stock), red dot (out of stock)
  - Optional: small image thumbnail (future)
  - Tap to add to order
  - Active/pressed: slight scale down (0.97)

**Right Column - Order Panel (340px):**
- Header: Order number + Table badge (e.g., "Masa 7" in blue pill)
- Item list (scrollable):
  - Each item row: quantity badge (blue) + name + modifiers (dim text) + price
  - Swipe left to delete (future)
  - Tap to edit quantity/modifiers
- Empty state: cart icon + "Urun ekleyerek baslayiniz"
- Totals section:
  - Subtotal
  - Tax (KDV)
  - Grand total (large, blue, bold)
- Action buttons:
  - Row 1: "Mutfaga Gonder" (orange, full width) - send to kitchen
  - Row 2: "Indirim" (secondary) + "Odeme" (green) - side by side

---

#### S04: Modifier Selection Dialog
**Purpose:** When product has modifiers (size, extras, cooking preference).
**Layout:** Modal/bottom sheet overlay on POS screen
**Elements:**
- Product name + price at top
- Modifier groups listed vertically:
  - Group name: "Boyut" (required badge if mandatory)
  - Options as pill buttons or radio/checkbox:
    - Single select: radio style (one active, blue)
    - Multi select: checkbox style (multiple active)
  - Each option: name + price delta (+CHF 2.00)
- Quantity selector: - [qty] + buttons
- Notes input: free text field "Ozel not ekleyin..."
- Bottom: "Iptal" (cancel) + "Ekle" (add, blue primary)

---

#### S05: Payment Screen
**Purpose:** Process payment for current order.
**Layout:** 2-column centered
- Left: Order summary (what they're paying for)
- Right: Payment method + amount entry

**Left Column - Summary:**
- Order # + Table name
- Item list (compact: name + price)
- Subtotal, tax, discount (if any)
- Grand total (large, blue)

**Right Column - Payment:**
- Payment method grid (2x2):
  - Cash (money icon) - default selected
  - Credit Card (card icon)
  - Debit Card (card icon)
  - Split Payment (scissors icon)
- Selected method: blue border
- Amount input display (large number)
- Numpad (3x4): digits + C (clear) + decimal point
- Quick amount buttons: "Tam" (exact), "150", "200", "Yuvarla" (round up)
- Change display: "Para Ustu: CHF 26.50" (green, large)
- "Complete Payment" button (green, full width, large)

**Split Payment sub-screen (when "Bol Ode" selected):**
- Options: "Esit Bol" (equal split), "Urun Bazli" (by item), "Ozel Tutar" (custom)
- Equal split: slider or number picker for guest count
- By item: checkboxes next to each item
- Custom: manual amount entry per payment

---

#### S06: Receipt Preview Screen
**Purpose:** Show receipt before/after printing, option to reprint.
**Layout:** Centered receipt card (resembling thermal paper)
**Elements:**
- White card on dark background (simulating receipt paper)
- Receipt content:
  - Restaurant name + address (centered)
  - Date, time, receipt number
  - Waiter name
  - Dashed line divider
  - Item list with quantities and prices
  - Subtotal, tax breakdown, total
  - Payment method + amount tendered + change
  - Dashed line
  - "Afiyet Olsun!" footer message
  - TSE data area (Germany - if applicable)
- Buttons below receipt:
  - "Yazdir" (Print - blue primary)
  - "E-posta Gonder" (email - secondary)
  - "Kapat" (close)

---

#### S07: Shift Close Screen
**Purpose:** End of shift - count cash, see summary, close.
**Layout:** 2-column
- Left: Shift summary (statistics)
- Right: Cash count + close action

**Left Column - Summary:**
- Shift info: date, time range, staff name
- Stats grid (2x2 cards):
  - Total Sales (green, large number)
  - Order Count
  - Average Order Value
  - Guest Count
- Payment breakdown:
  - Cash total
  - Credit card total
  - Debit card total
- Transactions:
  - Voids (count + amount, red)
  - Discounts (count + amount, orange)
  - Refunds (count + amount, red)

**Right Column - Cash Count:**
- "Kasadaki Nakit" input (large number)
- Variance display:
  - Expected amount
  - Difference (green if match, red if off)
- Notes field (optional)
- "Close Shift" button (blue, primary)

---

### PHASE 2: Restaurant Mode Screens (Priority: HIGH)

---

#### S08: Floor Plan / Table Map ⭐
**Purpose:** Visual overview of all tables, their status, navigate to table's order.
**Layout:** Left sidebar + main canvas

**Left Sidebar (200px):**
- Floor tabs: "Ana Salon", "Teras", "Bar", "VIP"
  - Active: blue highlight
- Stats at bottom:
  - Total tables, Occupied (red), Free (green), Reserved (blue), Dirty (orange)

**Main Canvas:**
- Grid/dot background (subtle)
- Table objects positioned on canvas:
  - Rectangle tables: various sizes
  - Round tables: circle shape
  - Colors by status:
    - Available/Free: green border + green tint bg
    - Occupied: red border + red tint bg
    - Reserved: blue border + blue tint bg
    - Dirty/Cleaning: orange border + orange tint bg
  - Each table shows:
    - Table number (large, centered): "M1", "M7", "B2", "L1"
    - Status text (small): "Bos", "Dolu", "Rezerve", "Kirli"
    - Time (if occupied): "45dk", "1s 15dk"
    - Guest count (if occupied): "4 kisi"
- Tap table:
  - If free: opens "Open Table" dialog
  - If occupied: navigates to that table's order in POS

---

#### S09: Open Table Dialog
**Purpose:** Start a new table session.
**Layout:** Modal overlay
**Elements:**
- Table number display (large)
- Guest count selector: - [count] + stepper
- Waiter assignment: dropdown or avatar picker
- Order type: "Dine In" (default) / "Takeaway" toggle
- Notes field (optional)
- "Masayi Ac" (Open Table) button - green

---

#### S10: Kitchen Display Screen (KDS) ⭐
**Purpose:** Kitchen staff sees incoming orders, marks items ready.
**Layout:** Full screen, horizontal scrolling ticket cards
**Theme:** Slightly different from POS - darker, orange accent to distinguish

**Top Bar:**
- "MUTFAK" title (orange, bold)
- Back to POS button
- Stats (right-aligned):
  - Pending count (red)
  - Preparing count (orange)
  - Completed count (green)
  - Average prep time

**Ticket Cards (horizontal scroll):**
- Each card: 240px wide, full height
- Card border color by age:
  - Fresh (<10min): green border
  - Warning (10-20min): orange border
  - Urgent (>20min): red border
- Header: Table name (large bold) + Timer (color-coded)
- Meta row: Order # + Waiter name
- Items list:
  - Quantity (large, blue) + Name (bold)
  - Modifiers below (orange text)
  - Special notes (yellow, italic)
  - Allergy warnings (red, with icon)
- Footer: "HAZIR" (READY) bump button (green, full width)
- Completed tickets slide left and disappear

**Course indicator:** If order has multiple courses:
- "Kurs 1" / "Kurs 2" label on ticket
- Fire next course button

---

#### S11: Split Bill Screen
**Purpose:** Split a table's bill between multiple guests.
**Layout:** Full screen overlay
**Elements:**
- Tab selector: "Esit Bol" | "Urun Bazli" | "Ozel Tutar"
- Equal Split:
  - Guest count slider/stepper
  - Shows: "CHF 123.50 / 3 = CHF 41.17 per person"
  - List of split amounts
- By Item:
  - Left: item list with checkboxes
  - Right: bills (Bill 1, Bill 2, ...) - drag items between bills
- Custom:
  - Manual amount entry per bill
  - Remaining amount display
- Each bill: separate payment button

---

#### S12: Merge Tables Dialog
**Purpose:** Combine two table sessions into one ticket.
**Layout:** Modal
**Elements:**
- Source table display
- Arrow
- Target table selector (grid of occupied tables)
- Preview: combined item list
- "Birlestir" (Merge) button

---

#### S13: Move Table Dialog
**Purpose:** Move a session from one table to another.
**Layout:** Modal
**Elements:**
- Current table display
- Arrow
- Available tables grid (only free tables shown)
- "Tasi" (Move) button

---

### PHASE 3: Cloud & Management Screens (Priority: MEDIUM)

---

#### S14: Device Pairing Screen
**Purpose:** Pair a new tablet with the restaurant's branch.
**Layout:** Centered
**Elements:**
- QR code display (for scanning from another device)
- OR manual code entry (6-digit code)
- Branch name + device name fields
- Device role selector: "POS", "KDS", "Kiosk"
- "Pair Device" button

---

#### S15: Back Office Lite (On-Device)
**Purpose:** Basic management on the tablet itself (menu edit, table edit, staff, reports).
**Layout:** Sidebar navigation + content area
**Sidebar Items:**
- Menu Management
- Table Management
- Staff Management
- Reports
- Printer Settings
- Restaurant Settings

**Sub-screens:**
- Menu Management: category list + product list, CRUD forms
- Table Management: floor plan editor (add/move/resize tables)
- Staff: user list + PIN management + role assignment
- Reports: daily sales chart, product mix table, shift history
- Printer: discovered printers, test print, assign to station (receipt/kitchen/bar)
- Settings: restaurant name, address, tax rates, currency, language

---

#### S16: Offline Warning Bar
**Purpose:** Persistent indicator when device is offline.
**Layout:** Top banner (not a screen, an overlay component)
**Elements:**
- Orange bar below top bar: "Cevrimdisi - Veriler yerel olarak kaydediliyor"
- Sync status: "Son senkronizasyon: 5 dk once"
- Pending items count: "3 islem bekliyor"
- When back online: green bar "Baglanildi - Senkronize ediliyor..." then disappears

---

#### S17: Manager Override Dialog
**Purpose:** Manager enters PIN to authorize a restricted action (void, refund, discount).
**Layout:** Small centered modal
**Elements:**
- Title: "Yetki Gerekli" (Authorization Required)
- Action description: "Urun iptali: 2x Adana Kebap (CHF 57.00)"
- Manager PIN input (4-6 dots)
- Small PIN pad
- Cancel + Confirm buttons
- Audit note: auto-logged with manager name + timestamp

---

#### S18: Refund Screen
**Purpose:** Process a refund for a previous order.
**Layout:** 2-column
**Elements:**
- Left: Original order details (items, amounts)
  - Checkboxes to select items for refund
  - "Select All" option
- Right: Refund summary
  - Selected items + amounts
  - Refund total
  - Refund method (original method or cash)
  - Reason dropdown: "Musteri memnuniyetsizligi", "Yanlis urun", "Kalite sorunu", "Diger"
  - Requires manager PIN (S17 overlay)
- "Iade Et" (Process Refund) button - red

---

### PHASE 4+: Future Screens (Priority: LOW - design later)

---

#### S19: Online Order Acceptance
- Incoming order notification popup
- Order details preview
- Accept / Reject / Modify + prep time buttons
- Order queue list

#### S20: QR Mobile Order (Customer-Facing Web)
- Mobile responsive menu
- Category browsing
- Product detail with modifiers
- Cart
- Order submission + status tracking
- Light theme (customer-facing)

#### S21: Kiosk Browse Screen
- Full-screen, large imagery
- Big category buttons with photos
- Product cards with large images
- Large touch targets (15.6" screen)
- Accessibility: high contrast, large text option

#### S22: Kiosk Checkout
- Order summary
- Payment terminal prompt ("Kartinizi okutunuz")
- Order number display after payment
- "Yeni Siparis" (New Order) restart

#### S23: Cloud Admin Dashboard (Web)
- Multi-branch overview map
- Revenue charts (line, bar)
- Device health grid
- Menu management interface
- User management
- License/subscription status
- This is a WEB interface, not tablet

---

## Component Library Needed

Design these reusable components:

### Buttons
- Primary (blue bg, white text)
- Success (green bg, white text)
- Warning (orange bg, dark text)
- Danger (red bg, white text)
- Secondary (card bg, border, white text)
- Ghost (transparent, text only)
- Icon button (square, icon only)
- Sizes: Small (32px), Medium (44px), Large (56px)

### Inputs
- Text input (dark bg, border)
- Number input (centered, large font)
- Search input (with icon)
- PIN input (dots)
- Dropdown/Select
- Toggle switch
- Stepper (- [value] +)

### Cards
- Product card (name + price)
- Order item row (qty + name + mods + price)
- Table object (number + status + time)
- KDS ticket card (header + items + bump button)
- Summary stat card (value + label)

### Badges / Pills
- Status badge: Online (green), Offline (orange), Syncing (blue pulse)
- Table badge: "Masa 7" (blue pill)
- Role badge: "Admin", "Garson", "Kasiyer"
- Count badge: red circle with number

### Dialogs / Modals
- Confirmation dialog (title + message + actions)
- Modifier selection modal
- Manager override modal
- Error dialog (red accent)

### Navigation
- Top bar (fixed, 56px)
- Category sidebar (vertical tabs)
- Floor tab selector
- Bottom sheet (slide up from bottom)

### Feedback
- Toast notification (success/error/info)
- Loading spinner
- Progress bar (sync progress)
- Empty state (icon + message)
- Skeleton loading (placeholder shimmer)

---

## Interaction Guidelines

1. **Tap = instant response.** No delays. Visual feedback within 50ms.
2. **Long press = secondary action** (edit, delete, details).
3. **Swipe left on order item = delete** with confirmation.
4. **Pull down = refresh** (where applicable).
5. **Double tap product = quick add** (quantity +1 without modifier dialog).
6. **Pinch zoom on floor plan** to zoom in/out (future).
7. **All destructive actions require confirmation** (void, delete, refund).
8. **Manager actions require PIN overlay** before execution.

---

## Responsive Notes

- Primary: 1280x800 landscape (10" tablet)
- KDS can be portrait (800x1280) - tickets stack vertically
- All screens must work at 1024x768 minimum (8" tablet)
- POS screen right panel collapses to bottom sheet on smaller screens
- No desktop/phone designs needed for MVP

---

## Deliverables Expected from Stitch

1. **Design System file**: Colors, typography, spacing, all component variants
2. **Screen designs for S01-S18**: All states (default, hover, active, error, empty, loading, offline)
3. **Component library**: All reusable components listed above
4. **Interaction specs**: Transitions, animations, touch feedback
5. **Export**: Figma or asset export ready for Flutter implementation
6. **Dark theme only** for MVP (light theme can come later)

---

## Reference Apps for Inspiration

- **Loyverse POS**: Simple, clean sales screen layout
- **SumUp POS**: Modern dark theme POS
- **Square POS**: Category + product grid + order panel layout
- **Toast POS**: Kitchen display design
- **Lightspeed Restaurant**: Table management floor plan
- **iZettle**: Payment flow simplicity

---

## Brand

- Name: **GastroCore**
- Style: "Gastro" in white/light, "Core" in accent blue
- Tone: Professional, modern, trustworthy
- No playful/cute design - this is a business tool
- Clean, minimal, functional
- Swiss precision meets Turkish hospitality
