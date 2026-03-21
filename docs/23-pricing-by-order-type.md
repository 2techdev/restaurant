# 23 - Pricing by Order Type (Dine-In / Takeaway / Delivery)

> How restaurants in Switzerland and Germany handle different pricing for
> dine-in, takeaway, and delivery -- legal background, common patterns,
> and our recommended data model for GastroCore.

---

## 1. Legal / Tax Background

### 1.1 Switzerland (MWSTG)

The Swiss VAT Act (Bundesgesetz ueber die Mehrwertsteuer, MWSTG) draws a
sharp line between **gastgewerbliche Leistung** (catering / restaurant
service) and **Lieferung von Lebensmitteln** (supply of foodstuffs).

| Category | VAT Rate (2025) | Applies to |
|---|---|---|
| Catering service (gastgewerbliche Leistung) | **8.1 %** (normal rate) | Food consumed on premises where the restaurant provides seating, service, plates, cutlery |
| Food supply (Lieferung) | **2.6 %** (reduced rate) | Take-away food, home delivery of food, vending machines |
| Beverages (all contexts) | **8.1 %** (normal rate) | Alcoholic and non-alcoholic beverages, regardless of where consumed |

**Key legal definitions:**

- A meal is a *catering service* when the restaurant prepares or serves
  food at the customer's location, or provides facilities for on-site
  consumption (tables, chairs, counters).
- A meal is a *food supply* when it is packaged for takeaway or delivered
  to the customer's home/office. Home delivery of pizzas, for example, is
  classified as a food supply.
- **Grey area:** A takeaway counter next to a seating area may still be
  classified as catering if customers can sit down to eat. The restaurant
  must implement organisational separation (separate accounting,
  packaging for takeaway) to claim the reduced rate. Spatial separation
  is not required, but organisational separation is.

**Legal basis:** MWSTG Art. 25 (tax rates); ESTV Branchen-Info 08
(Gastgewerbe) defines the boundary between catering and food supply.

**Delivery platforms (2025 change):** From 1 January 2025, delivery
platforms (Uber Eats, Just Eat, Wolt) must themselves account for VAT on
the full delivery value, even if they do not operate a kitchen. This
shifts VAT liability to the platform for delivered orders.

### 1.2 Germany (UStG)

Germany's situation has undergone significant changes:

**Until 31 December 2025:**

| Category | VAT Rate | Applies to |
|---|---|---|
| Restaurant / catering service | **19 %** (standard rate) | Food consumed on premises with service |
| Takeaway food | **7 %** (reduced rate) | Food packaged for takeaway |
| Delivered food | **7 %** (reduced rate) | Food delivered to customer |
| Beverages (all contexts) | **19 %** (standard rate) | All beverages, regardless of consumption location |

**From 1 January 2026 (permanent change):**

| Category | VAT Rate | Applies to |
|---|---|---|
| All food (dine-in, takeaway, delivery) | **7 %** (reduced rate) | All prepared food regardless of consumption method |
| Beverages (all contexts) | **19 %** (standard rate) | All beverages except milk-based drinks with >75% milk content |

**Legal basis:** UStG paragraph 12 Abs. 2 Nr. 15 (new), introduced by the
Steueraenderungsgesetz 2025. Passed by Bundestag on 4 December 2025,
approved by Bundesrat on 19 December 2025. This is a **permanent**
change, not a temporary measure like the COVID-era reduction (2020-2023).

**Key implication for Germany from 2026:** The VAT distinction between
dine-in and takeaway food is eliminated. However, the food vs. beverage
distinction remains critical (7% vs 19%), and restaurants still need to
track order type for operational, reporting, and pricing reasons.

### 1.3 Summary Comparison (as of March 2026)

| | Switzerland | Germany (from 2026) |
|---|---|---|
| Dine-in food | 8.1% | 7% |
| Takeaway food | 2.6% | 7% |
| Delivery food | 2.6% | 7% |
| Beverages (all) | 8.1% | 19% |
| VAT gap (food, dine-in vs takeaway) | **5.5 pp** | **0 pp** |

**Switzerland** still has a significant VAT differential on food between
dine-in and takeaway/delivery. **Germany** has eliminated it from 2026.

---

## 2. Does the Law Require Different Prices?

**No.** Neither Swiss nor German law mandates that restaurants charge
different gross prices for dine-in vs. takeaway. The law only mandates
that the correct VAT rate is applied and reported.

This means:

- **In Switzerland:** If a pizza costs CHF 20 dine-in (incl. 8.1% VAT)
  and the restaurant charges CHF 20 takeaway (incl. 2.6% VAT), the
  restaurant simply retains more net revenue on the takeaway sale. This
  is perfectly legal.
- **In Germany (from 2026):** Since VAT on food is 7% in all cases,
  there is no tax-driven reason to differentiate food prices by order
  type. Any price differences are purely a business decision.

The restaurant chooses its pricing strategy. The tax authority only cares
that the VAT is correctly calculated and remitted.

---

## 3. Net vs Gross: How Does the Math Work?

When VAT rates differ between order types, there are two possible
approaches to pricing:

### Pattern A: Same Gross Price (most common)

The customer pays the same price regardless of order type. The restaurant's
net revenue differs.

**Example: Pizza listed at CHF 20.00 in Switzerland**

| | Dine-in (8.1%) | Takeaway (2.6%) |
|---|---|---|
| Gross price (what customer pays) | CHF 20.00 | CHF 20.00 |
| VAT amount | CHF 1.50 | CHF 0.51 |
| Net revenue (restaurant keeps) | CHF 18.50 | CHF 19.49 |
| **Extra margin on takeaway** | | **+CHF 0.99** |

The restaurant earns more net revenue on takeaway because less VAT is
owed. This is the simplest approach and by far the most common in
practice.

### Pattern B: Same Net Price (different gross)

The restaurant targets the same net revenue regardless of order type. The
customer pays less for takeaway.

**Example: Target net revenue of CHF 18.50**

| | Dine-in (8.1%) | Takeaway (2.6%) |
|---|---|---|
| Net revenue | CHF 18.50 | CHF 18.50 |
| VAT amount | CHF 1.50 | CHF 0.48 |
| Gross price (what customer pays) | CHF 20.00 | CHF 18.98 |
| **Takeaway discount** | | **-CHF 1.02** |

This is less common because it creates odd prices and requires separate
price displays.

### Pattern C: Explicit Takeaway Discount

The restaurant sets a base gross price and applies an explicit percentage
or fixed discount for takeaway orders. This may or may not correspond
exactly to the VAT difference.

**Example: CHF 20 base, 15% takeaway discount**

| | Dine-in | Takeaway (-15%) |
|---|---|---|
| Gross price | CHF 20.00 | CHF 17.00 |

The discount can exceed the VAT saving (restaurant passes savings plus
extra to attract takeaway customers) or be less than the VAT saving.

### Pattern D: Delivery Surcharge

Delivery orders may cost more due to delivery logistics, packaging, and
platform commissions. This is independent of VAT.

**Example: CHF 20 base, +CHF 3 delivery**

| | Dine-in | Delivery |
|---|---|---|
| Gross price | CHF 20.00 | CHF 23.00 |

Note: The delivery fee itself may be charged by the platform separately,
or baked into higher menu prices on delivery platforms.

---

## 4. Common Patterns in Practice

### 4.1 What Most Restaurants Actually Do

Based on research and industry practice:

1. **Pattern A (same gross price) is dominant.** The vast majority of
   restaurants in both Switzerland and Germany display one price and
   charge it regardless of order type. They quietly earn more margin on
   takeaway in Switzerland due to the VAT difference.

2. **Takeaway discounts exist but are a business choice.** Some
   restaurants offer 5-15% takeaway discounts to incentivise takeaway
   (lower service cost, no table turnover needed, no dishes to wash).
   This is a competitive/operational decision, not a tax requirement.

3. **Delivery prices are often higher.** When restaurants list on Uber
   Eats, Wolt, or Lieferando, they commonly increase menu prices by
   15-30% to offset the platform commission (typically 15-30%). The
   platform may also add a separate delivery fee charged to the customer.

4. **Multi-price menus are rare but growing.** A pizza might be:
   - Dine-in: CHF 20
   - Takeaway: CHF 17 (discount for no service)
   - Delivery: CHF 23 (surcharge for delivery cost)

### 4.2 Delivery Platform Pricing

Platforms like Uber Eats, Wolt, and Lieferando typically:

- Allow restaurants to set **separate menus/prices** for the platform
  vs. in-house
- Charge commissions of 13-30% on order value
- Add a separate delivery fee to the customer (charged by platform)
- Handle their own VAT accounting (especially in Switzerland from 2025)

Restaurants commonly raise delivery prices to cover commissions, meaning
the same dish can have 3 different prices across channels.

### 4.3 Real-World Example

A typical Swiss pizzeria might price a Margherita as follows:

| Channel | Gross Price | VAT Rate | Net Revenue | Notes |
|---|---|---|---|---|
| Dine-in | CHF 18.00 | 8.1% | CHF 16.65 | Base price |
| Takeaway | CHF 15.00 | 2.6% | CHF 14.62 | Discount to attract walk-ins |
| Own delivery | CHF 21.00 | 2.6% | CHF 20.47 | Covers driver cost |
| Uber Eats | CHF 22.00 | 2.6%* | CHF 21.44* | Covers 30% commission |

*VAT on platform deliveries from 2025 is handled by the platform itself.

---

## 5. How POS Systems Typically Implement This

Modern POS/Kassensystem solutions handle order-type pricing in several
ways:

### 5.1 Single Price + VAT Auto-Switch

The simplest approach: one menu price, but the POS automatically applies
the correct VAT rate based on order type (dine-in vs. takeaway). The
gross price stays the same; the receipt shows different VAT breakdowns.

**Pros:** Simple menu management, one price list.
**Cons:** Cannot offer takeaway discounts or delivery surcharges.

### 5.2 Price Overrides per Order Type

The product has a base price, but the POS allows setting overrides per
order type (or per sales channel). When an order is placed, the system
picks the price matching the order type.

**Pros:** Full flexibility.
**Cons:** More complex menu management (N prices per item).

### 5.3 Automatic Discounts/Surcharges by Order Type

The product has one base price, but rules are defined:
- Takeaway: apply -10% discount
- Delivery: apply +15% surcharge

**Pros:** Easy to manage (one base price + rules).
**Cons:** Rules may not fit all items equally.

### 5.4 Separate Menus per Channel

Some systems maintain entirely separate menus for dine-in, takeaway, and
delivery (especially for delivery platforms that have their own menu
management).

**Pros:** Complete independence.
**Cons:** Duplication, hard to keep in sync.

---

## 6. Recommended Approach for GastroCore

### 6.1 Design Principles

1. **Maximum flexibility:** Support all patterns (A through D and
   combinations). Different restaurants have different strategies.
2. **Tax correctness by default:** The system must always apply the
   correct VAT rate for the order type and country. This is non-negotiable.
3. **Simple default, powerful override:** Most restaurants want Pattern A
   (one price, auto VAT). Power users want per-order-type pricing.
4. **Channel awareness:** Delivery platforms are a distinct channel with
   distinct pricing needs.

### 6.2 How It Should Work

**Default behaviour (zero configuration):**
- Restaurant sets ONE price per menu item
- System applies the correct VAT rate based on order type
- Gross price is the same for all order types (Pattern A)
- Net revenue varies automatically

**Optional overrides (per restaurant preference):**
- Per-item price overrides for specific order types
- Percentage or fixed discount/surcharge rules per order type
- Separate price lists per sales channel (e.g., Uber Eats menu)

### 6.3 Order Types to Support

| Order Type Key | Label (EN) | Label (DE) | Default VAT (CH) | Default VAT (DE, 2026) |
|---|---|---|---|---|
| `DINE_IN` | Dine-in | Vor Ort | 8.1% (food), 8.1% (bev) | 7% (food), 19% (bev) |
| `TAKEAWAY` | Takeaway | Mitnehmen / Take-away | 2.6% (food), 8.1% (bev) | 7% (food), 19% (bev) |
| `DELIVERY` | Delivery | Lieferung | 2.6% (food), 8.1% (bev) | 7% (food), 19% (bev) |
| `PLATFORM` | Platform delivery | Plattform-Lieferung | 2.6%* (food) | 7% (food), 19% (bev) |

*Platform deliveries in Switzerland from 2025: VAT on the full delivery
value is accounted for by the platform, not the restaurant.

---

## 7. Data Model Implications

### 7.1 Core Entities

```
OrderType
---------
id              : uuid / PK
key             : enum [DINE_IN, TAKEAWAY, DELIVERY, PLATFORM]
label_en        : string
label_de        : string
is_active       : boolean
sort_order      : int
```

```
TaxProfile
----------
id              : uuid / PK
country_code    : string [CH, DE, AT, ...]
order_type_id   : FK -> OrderType
product_category: enum [FOOD, BEVERAGE, ALCOHOL, ...]
vat_rate        : decimal          -- e.g. 8.1, 2.6, 7.0, 19.0
valid_from      : date
valid_to        : date | null      -- null = currently active
```

The TaxProfile table encodes the matrix: for a given country + order type
+ product category, what VAT rate applies? The `valid_from` / `valid_to`
columns handle rate changes over time (e.g., Germany's switch on
2026-01-01).

```
ProductPrice
------------
id              : uuid / PK
product_id      : FK -> Product
price_list_id   : FK -> PriceList
order_type_id   : FK -> OrderType | null  -- null = default (all types)
gross_price     : decimal
currency        : string [CHF, EUR]
valid_from      : date
valid_to        : date | null
```

When `order_type_id` is NULL, the price applies to all order types
(Pattern A). When set, it applies only to that order type, enabling
per-type pricing (Patterns B/C/D).

```
OrderTypePriceRule
------------------
id              : uuid / PK
tenant_id       : FK -> Tenant
order_type_id   : FK -> OrderType
rule_type       : enum [PERCENTAGE_DISCOUNT, PERCENTAGE_SURCHARGE,
                        FIXED_DISCOUNT, FIXED_SURCHARGE]
value           : decimal          -- e.g. 10.0 for 10%, or 2.00 for CHF 2
applies_to      : enum [ALL_PRODUCTS, CATEGORY, SPECIFIC_PRODUCT]
category_id     : FK -> Category | null
product_id      : FK -> Product | null
is_active       : boolean
valid_from      : date
valid_to        : date | null
```

This table supports rules like "all takeaway orders get 10% off" or
"delivery orders for pizza category get +CHF 3 surcharge".

### 7.2 Price Resolution Algorithm

When calculating the price for a product on an order:

```
1. Look up ProductPrice where product_id matches
   AND (order_type_id = current_order_type OR order_type_id IS NULL)
   AND valid_from <= today AND (valid_to IS NULL OR valid_to >= today)

2. If a specific order_type match exists, use it (most specific wins).
   Otherwise, use the NULL (default) price.

3. Apply any active OrderTypePriceRule for this order type + product.

4. Look up TaxProfile for country + order_type + product_category
   to get the applicable VAT rate.

5. Calculate:
   - net_price = gross_price / (1 + vat_rate/100)
   - vat_amount = gross_price - net_price

6. Return { gross_price, net_price, vat_rate, vat_amount }
```

### 7.3 Order Line Extension

The order line item must store which order type was used and the resolved
tax details:

```
OrderLine (additional fields)
-----------------------------
order_type_id   : FK -> OrderType    -- inherited from Order, but stored
                                       per-line for audit
applied_vat_rate: decimal            -- the actual rate applied
net_amount      : decimal            -- price excl. VAT
vat_amount      : decimal            -- VAT portion
gross_amount    : decimal            -- price incl. VAT
price_rule_id   : FK -> OrderTypePriceRule | null  -- if a rule was applied
```

### 7.4 Example Data

**TaxProfile rows for Switzerland (2025):**

| country | order_type | product_category | vat_rate | valid_from |
|---|---|---|---|---|
| CH | DINE_IN | FOOD | 8.1 | 2024-01-01 |
| CH | TAKEAWAY | FOOD | 2.6 | 2024-01-01 |
| CH | DELIVERY | FOOD | 2.6 | 2024-01-01 |
| CH | * | BEVERAGE | 8.1 | 2024-01-01 |

**TaxProfile rows for Germany:**

| country | order_type | product_category | vat_rate | valid_from | valid_to |
|---|---|---|---|---|---|
| DE | DINE_IN | FOOD | 19.0 | 2024-01-01 | 2025-12-31 |
| DE | TAKEAWAY | FOOD | 7.0 | 2024-01-01 | 2025-12-31 |
| DE | DELIVERY | FOOD | 7.0 | 2024-01-01 | 2025-12-31 |
| DE | * | FOOD | 7.0 | 2026-01-01 | null |
| DE | * | BEVERAGE | 19.0 | 2024-01-01 | null |

**ProductPrice rows (Swiss pizzeria example):**

| product | order_type | gross_price | currency |
|---|---|---|---|
| Margherita | null (all) | 20.00 | CHF |
| Margherita | TAKEAWAY | 17.00 | CHF |
| Margherita | DELIVERY | 23.00 | CHF |

---

## 8. Edge Cases and Considerations

### 8.1 Order Type Change Mid-Order

A customer orders dine-in but then asks to take the remaining food home.
The order type for those items should remain DINE_IN (the service was
provided). Only items explicitly ordered for takeaway should be TAKEAWAY.

### 8.2 Mixed Orders

An order might contain dine-in and takeaway items (e.g., eating a pizza
at the restaurant and buying a second one to take home). Each line item
should carry its own order type and VAT rate.

### 8.3 Beverages Are Always Standard Rate (Switzerland)

In Switzerland, beverages are taxed at 8.1% regardless of order type.
The system must not apply the reduced 2.6% rate to beverages on takeaway
orders. The product category (FOOD vs BEVERAGE) determines this.

### 8.4 Beverages in Germany (2026)

In Germany from 2026, beverages remain at 19% while food drops to 7%.
Milk-based drinks with >75% milk content are an exception and qualify for
7%. The system needs a way to flag specific beverages as milk-based.

### 8.5 Platform Orders

For platform deliveries (Uber Eats, Wolt, Lieferando):
- The platform typically has its own menu and prices
- In Switzerland (from 2025), the platform handles VAT accounting on the
  full delivery value
- The restaurant receives the order value minus commission
- GastroCore should import platform orders with the platform-specific
  prices and mark them as PLATFORM order type

### 8.6 Vouchers and Coupons

From 2026 in Germany, vouchers covering both food and beverages are
treated as multi-purpose vouchers (since different VAT rates apply). VAT
is calculated at redemption, not at issuance.

---

## 9. Summary of Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Default pricing pattern | Pattern A (same gross, VAT auto-adjusts) | Simplest, most common, zero config |
| Per-type pricing | Supported via ProductPrice overrides | Needed for restaurants with takeaway discounts or delivery surcharges |
| Per-type rules | Supported via OrderTypePriceRule | Enables "all takeaway -10%" without per-item config |
| VAT resolution | TaxProfile lookup by country + order type + category | Handles CH/DE differences and future rate changes |
| Order line storage | Store resolved VAT rate and amounts per line | Required for correct receipts, reporting, and audit |
| Platform orders | Separate order type (PLATFORM) | Different pricing, VAT handling, and commission tracking |
| Mixed orders | Per-line order type | Handles edge case of mixed dine-in/takeaway |

---

## 10. References

- Swiss Federal Tax Administration (ESTV): MWST Branchen-Info 08 - Gastgewerbe
  https://www.swissvat.ch/fileadmin/user_upload/MBI08_06.02.2025.pdf
- Gastroconsult: Steuertipp Take-away
  https://www.gastroconsult.ch/de/page/News/Steuertipp-Verkaeufe-ueber-die-Gasse-Take-away-71698
- Findea: Gastgewerbliche Leistung und Lieferung
  https://blog.findea.ch/de-blog/de-steuern-der-unterschied-zwischen-gastgewerblicher-leistung-und-lieferung-von-lebensmitteln
- SIDES: Mehrwertsteuer in der Gastronomie Schweiz 2025
  https://www.get-sides.ch/blog/mehrwertsteuer-gastronomie/
- Das Pauli Magazin: MWST und Uber Eats 2025
  https://daspaulimagazin.ch/de/freitext/gesetz-mwst-schweizer-restaurants-haften-fur-die-mwst-rechnung-von-ubereats
- ZDH: Ermaessigter Umsatzsteuersatz Gastronomie ab 2026
  https://www.zdh.de/ueber-uns/fachbereich-steuern-und-finanzen/umsatzsteuer/ermaessigter-umsatzsteuersatz-fuer-die-gastronomie-ab-112026/
- Marosa VAT: Germany VAT Rate Changes 2026
  https://marosavat.com/vat-news/german-vat-rate-changes
- DLA Piper: Permanent VAT Reduction for Gastronomy
  https://www.dlapiper.com/en/insights/publications/indirect-tax-monthly-alert-series/2025/monthly-indirect-tax-alert-november-2025/permanent-vat-reduction-for-gastronomy-and-extended-transition-for-public-sector
- VATUpdate: Germany Cuts Restaurant Food VAT to 7% from 2026
  https://www.vatupdate.com/2025/12/30/germany-cuts-restaurant-food-vat-to-7-from-2026-unifying-dine-in-takeaway-and-delivery-rates/
- Sevdesk: Mehrwertsteuer in der Gastronomie 2026
  https://sevdesk.de/ratgeber/buchhaltung-finanzen/steuern/umsatzsteuer/mehrwertsteuer-gastronomie/
