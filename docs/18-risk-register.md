# 18 - Risk Register

> Comprehensive risk identification, assessment, and mitigation plan for GastroCore.

---

## 1. Risk Assessment Methodology

Each risk is evaluated on two dimensions:

- **Impact (1-5):** How severe would it be if this risk materializes?
  - 1 = Negligible (minor inconvenience)
  - 2 = Low (workaround exists, limited users affected)
  - 3 = Moderate (feature degraded, several users affected)
  - 4 = High (major feature broken, many users affected, revenue impact)
  - 5 = Critical (legal liability, data loss, business-threatening)

- **Likelihood (1-5):** How probable is this risk?
  - 1 = Rare (unlikely to occur)
  - 2 = Unlikely (could happen but improbable)
  - 3 = Possible (reasonable chance)
  - 4 = Likely (more probable than not)
  - 5 = Almost certain (will happen without mitigation)

- **Risk Score = Impact x Likelihood** (range: 1-25)

**Risk Thresholds:**

| Score   | Level    | Action Required                                  |
|---------|----------|--------------------------------------------------|
| 1-4     | Low      | Accept and monitor                               |
| 5-9     | Medium   | Mitigation plan required, review quarterly        |
| 10-15   | High     | Active mitigation, review monthly                 |
| 16-25   | Critical | Immediate mitigation, review weekly               |

---

## 2. Risk Heatmap

```
            IMPACT →
LIKELIHOOD  1       2       3       4       5
    ↓
    5       R-27    R-17    R-08    -       -
    4       R-20    R-24    R-05    R-04    R-01
                    R-26    R-19
    3       -       R-25    R-09    R-03    R-02
                            R-10    R-06
                            R-16    R-13
                            R-18    R-22
    2       -       R-15    R-23    R-07    R-14
                                    R-11
                                    R-21
    1       -       -       R-12    -       -
```

---

## 3. Risk Register

### Compliance Risks

---

#### R-01: Germany Fiscal Non-Compliance

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-01                                                                |
| **Category**     | Compliance                                                          |
| **Description**  | Failure to comply with German KassenSichV (cash register security regulation) could result in fines of up to EUR 25,000 per violation. Non-compliant POS systems cannot legally operate in Germany. If our TSE integration is incomplete or incorrect, every customer using our system in Germany is at legal risk. |
| **Impact**       | 5 -- Legal penalties for customers, product banned from German market |
| **Likelihood**   | 4 -- Fiscal compliance is complex; edge cases are numerous          |
| **Risk Score**   | **20 (Critical)**                                                   |
| **Mitigation**   | 1. Engage German tax advisor before starting Phase 4. 2. Use Fiskaly SIGN DE v2 (certified cloud TSE) to avoid hardware TSE complexity. 3. Test every transaction type against DSFinV-K validator. 4. Run 1000-transaction fiscal stress test before pilot. 5. Maintain audit log that meets GoBD requirements from day 1. 6. Plan for Fiskaly certification review. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-02: Fiskaly API Breaking Changes

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-02                                                                |
| **Category**     | Technical / Compliance                                              |
| **Description**  | Fiskaly may release API v3 or make breaking changes to v2 that require significant rework of our TSE integration. Since Fiskaly is our sole TSE provider, we have a single point of dependency. API deprecation could break fiscal compliance overnight. |
| **Impact**       | 5 -- Fiscal signing would fail, requiring emergency hotfix           |
| **Likelihood**   | 3 -- API providers do make breaking changes, but typically with notice |
| **Risk Score**   | **15 (High)**                                                       |
| **Mitigation**   | 1. Pin to specific API version (v2). 2. Isolate Fiskaly calls behind an adapter/interface (Fiscal Gateway pattern). 3. Monitor Fiskaly changelog and developer announcements. 4. Maintain relationship with Fiskaly developer support. 5. Design adapter so alternative TSE providers could be swapped in (long-term). |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-15: GDPR Violation (Customer Data)

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-15                                                                |
| **Category**     | Compliance                                                          |
| **Description**  | Storing or processing customer personal data (names, phone numbers from online ordering, staff performance data) without proper GDPR compliance. Fines can reach EUR 20M or 4% of annual revenue. Also Swiss nDSG (new Federal Act on Data Protection) compliance required. |
| **Impact**       | 5 -- Massive fines, reputation destruction                          |
| **Likelihood**   | 2 -- Low if we design for privacy from the start                    |
| **Risk Score**   | **10 (High)**                                                       |
| **Mitigation**   | 1. Minimize personal data collection (no customer accounts in MVP). 2. Data processing agreement template for tenants. 3. Staff performance reports restricted to manager role. 4. Data retention policies with automatic purge. 5. Privacy-by-design: no analytics tracking of end customers. 6. Document data flows and maintain ROPA (Record of Processing Activities). |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-16: Swiss VAT Rate Change

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-16                                                                |
| **Category**     | Compliance                                                          |
| **Description**  | Swiss government changes VAT rates (as happened in January 2024: 7.7% to 8.1%). If our system hardcodes rates or cannot handle rate transitions (old rate for orders before cutoff, new rate after), all Swiss customers would calculate tax incorrectly. |
| **Impact**       | 3 -- Incorrect tax on receipts, potential audit issues for customers |
| **Likelihood**   | 3 -- Rate changes happen every few years                            |
| **Risk Score**   | **9 (Medium)**                                                      |
| **Mitigation**   | 1. Store tax rates in configuration, never hardcode. 2. Support effective dates on tax rates (new rate activates automatically on date). 3. Admin can configure future rates in advance. 4. Orders locked with the tax rate at time of sale (immutable). 5. Test rate transition scenario in integration tests. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

### Technical Risks

---

#### R-03: Offline Data Loss (Device Failure)

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-03                                                                |
| **Category**     | Technical                                                           |
| **Description**  | A tablet hardware failure (drop, water damage, battery death) during service could lose unsynced local data. In offline-first mode, the device may hold hours of transaction data not yet synced to cloud. Data loss means lost revenue records and potential fiscal compliance gaps. |
| **Impact**       | 4 -- Lost transactions, fiscal gaps, revenue discrepancy            |
| **Likelihood**   | 3 -- Tablets do fail, especially in restaurant environments         |
| **Risk Score**   | **12 (High)**                                                       |
| **Mitigation**   | 1. Aggressive sync: push data to cloud every 30 seconds when connected. 2. Local SQLite WAL mode for crash resilience. 3. Recommend restaurants keep a spare tablet. 4. Shift close report printed/exported as backup. 5. In multi-device setup, secondary has copy of data. 6. Recovery procedure documented for restoring from cloud to new device. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-04: Sync Conflicts Causing Data Corruption

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-04                                                                |
| **Category**     | Technical                                                           |
| **Description**  | When multiple devices edit the same data offline (e.g., two waiters modify the same table's order), sync conflicts could corrupt data, duplicate items, or lose changes. This is the hardest distributed systems problem in the product. |
| **Impact**       | 4 -- Incorrect orders, double charges, lost items                   |
| **Likelihood**   | 4 -- Multi-device with offline periods makes conflicts inevitable   |
| **Risk Score**   | **16 (Critical)**                                                   |
| **Mitigation**   | 1. CRDT-inspired conflict resolution: last-writer-wins for simple fields, union-merge for collections (order items). 2. Each device owns its operations (device_id on every record). 3. Orders are append-only (add items, don't edit). 4. Conflict log: record every conflict for debugging. 5. Extensive sync simulation tests (10+ devices, random network loss). 6. Start simple: primary/secondary model in Phase 2 avoids most conflicts. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-05: Hardware Printer Diversity

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-05                                                                |
| **Category**     | Technical                                                           |
| **Description**  | There are 100+ thermal receipt printer models in the market, each with slight ESC/POS command variations. Supporting even 10 models requires significant testing. Bluetooth connectivity varies widely between Android devices and printer brands. |
| **Impact**       | 3 -- Printing failures frustrate users and block sales              |
| **Likelihood**   | 4 -- Printer diversity is a known industry challenge                |
| **Risk Score**   | **12 (High)**                                                       |
| **Mitigation**   | 1. Support 2-3 specific printer models at launch (Epson TM-m30, Star SM-L200, MUNBYN). 2. Recommend these models to customers. 3. Use standard ESC/POS subset (avoid printer-specific commands). 4. Printer configuration: paper width, encoding, cut command as settings. 5. Test print page in app for customer to verify before going live. 6. Community-reported compatibility list over time. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-06: Export API Compatibility with Custom Backoffice

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-06                                                                |
| **Category**     | Technical                                                           |
| **Description**  | The custom backoffice (team's own infrastructure) consumes GastroCore's export API. If export format changes between GastroCore versions, the custom backoffice may break. Schema mismatch could cause accounting data gaps. **NOTE: ERPNext has been removed — this risk is now about the export API contract between GastroCore and the custom backoffice.** |
| **Impact**       | 3 -- Accounting data gap until custom backoffice is updated         |
| **Likelihood**   | 2 -- Export schema changes are infrequent and under team control    |
| **Risk Score**   | **6 (Medium)**                                                      |
| **Mitigation**   | 1. Version the export API: `/api/v1/export/...` — never break without new version. 2. Document export schema changes in CHANGELOG. 3. Custom backoffice team reviews GastroCore release notes before updating. 4. Maintain backward-compatible export format for at least 2 versions. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open (reduced from High to Medium — ERPNext fragility removed)      |

---

#### R-07: Flutter Breaking Changes on Major Version

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-07                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Flutter major version upgrades (3.x to 4.x) may introduce breaking changes in UI rendering, plugin APIs, or Dart language features. The Drift ORM, Bluetooth plugins, and printing libraries may lag behind, creating dependency conflicts. |
| **Impact**       | 4 -- App may not build/run after upgrade, blocking all development  |
| **Likelihood**   | 2 -- Flutter team provides migration guides; breaking changes are managed |
| **Risk Score**   | **8 (Medium)**                                                      |
| **Mitigation**   | 1. Pin Flutter SDK version in project. 2. Upgrade only after critical plugins confirm compatibility. 3. Maintain comprehensive test suite to catch regressions. 4. Follow Flutter stable channel, not beta. 5. Budget 1-2 weeks per year for framework upgrades. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-17: Network Reliability in Rural Restaurants

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-17                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Rural restaurants in Switzerland and Germany may have unreliable internet (slow DSL, no fiber, spotty 4G). Extended offline periods (hours or days) stress the offline-first architecture and delay cloud sync. Fiscal signing (Germany) requires connectivity. |
| **Impact**       | 3 -- Delayed sync, fiscal signing queue grows, cloud reports stale  |
| **Likelihood**   | 5 -- Rural connectivity issues are common in both markets           |
| **Risk Score**   | **15 (High)**                                                       |
| **Mitigation**   | 1. Offline-first architecture is the primary mitigation. 2. Device operates fully without cloud for days. 3. Fiscal signing queue tolerates 500+ pending transactions. 4. Sync uses delta compression to minimize bandwidth. 5. Test on throttled connections (2G, 3G simulation). 6. Recommend 4G router as backup internet for German restaurants (fiscal signing). |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-18: Tablet Hardware Failure Mid-Service

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-18                                                                |
| **Category**     | Technical / Operational                                             |
| **Description**  | Primary tablet crashes, runs out of battery, or breaks during peak dinner service. If it is the only device, the restaurant cannot take orders or process payments until a replacement is configured. |
| **Impact**       | 3 -- Service disruption for 30-60 minutes                          |
| **Likelihood**   | 3 -- Hardware failures are inevitable over time                     |
| **Risk Score**   | **9 (Medium)**                                                      |
| **Mitigation**   | 1. Recommend spare tablet (pre-configured, on standby). 2. Fast device setup: new device syncs from cloud in <5 minutes. 3. Battery monitoring alert at 20%. 4. Charging station recommendation in hardware guide. 5. Paper order pad as ultimate fallback (documented in onboarding). |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-19: Kitchen Display Latency in LAN Sync

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-19                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Kitchen Display Screen must show new orders within 2-3 seconds. Over WiFi LAN, latency spikes, dropped packets, or WiFi congestion during peak hours could delay kitchen tickets, slowing food preparation and frustrating staff. |
| **Impact**       | 3 -- Kitchen delays, food quality issues, staff frustration         |
| **Likelihood**   | 4 -- WiFi in commercial kitchens is notoriously unreliable          |
| **Risk Score**   | **12 (High)**                                                       |
| **Mitigation**   | 1. Direct socket connection (WebSocket or TCP) between POS and KDS, not polling. 2. Audible alert on KDS for new tickets (staff hears even if screen isn't watched). 3. Heartbeat mechanism: KDS shows "disconnected" warning if no signal in 5 seconds. 4. Recommend dedicated WiFi access point for POS/KDS network. 5. Fallback: print kitchen ticket on network printer if KDS is unreachable. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-21: Cloud Infrastructure Downtime

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-21                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Cloud backend downtime (server crash, hosting provider outage, database failure) would prevent sync, web dashboard access, online ordering, and fiscal signing for German customers. Extended outage would delay fiscal compliance. |
| **Impact**       | 4 -- No sync, no dashboard, no online orders, fiscal signing queue  |
| **Likelihood**   | 2 -- Managed hosting achieves 99.9% uptime; outages are rare but happen |
| **Risk Score**   | **8 (Medium)**                                                      |
| **Mitigation**   | 1. Offline-first: POS continues operating during cloud outage. 2. Automated database backups every 6 hours. 3. Health monitoring with alerting (uptime check every 60 seconds). 4. Documented disaster recovery procedure. 5. Target: recovery within 1 hour. 6. Consider multi-region setup after 50+ tenants. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-23: Scaling Beyond 100 Tenants

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-23                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Initial architecture (single PostgreSQL, single Go server) may not scale beyond 100 concurrent tenants. Database connection pooling, sync throughput, and materialized view refresh could become bottlenecks. |
| **Impact**       | 3 -- Performance degradation, slow sync, slow reports               |
| **Likelihood**   | 2 -- Reaching 100 tenants is a good problem to have; architecture handles dozens easily |
| **Risk Score**   | **6 (Medium)**                                                      |
| **Mitigation**   | 1. Design for scale but don't build for it prematurely. 2. Tenant isolation via row-level security (can shard later). 3. Connection pooling (PgBouncer). 4. Materialized view refresh staggered across tenants. 5. Load testing at 100 tenants before scaling is needed. 6. Clear upgrade path: read replicas, then sharding if needed. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-26: Android OS Fragmentation

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-26                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Android tablets range from Android 8 to 14, with different manufacturers (Samsung, Lenovo, Huawei, generic Chinese brands). Bluetooth behavior, WiFi handling, background process management, and permission models differ significantly. Some budget tablets have buggy Bluetooth stacks. |
| **Impact**       | 2 -- Printing or connectivity issues on specific devices            |
| **Likelihood**   | 4 -- Android fragmentation is a documented industry problem         |
| **Risk Score**   | **8 (Medium)**                                                      |
| **Mitigation**   | 1. Set minimum Android version to 10 (API 29). 2. Recommend 2-3 specific tablet models (tested and certified). 3. Maintain compatibility matrix (tested device + OS combinations). 4. Flutter abstracts most OS differences. 5. Bluetooth abstraction layer to handle device-specific quirks. 6. Customer support: "use recommended hardware" as first troubleshooting step. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-27: Bluetooth Connection Instability

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-27                                                                |
| **Category**     | Technical                                                           |
| **Description**  | Bluetooth connections to thermal printers are inherently unstable. Android's Bluetooth stack varies by manufacturer, connections drop during high-traffic WiFi environments (2.4 GHz interference), and reconnection is slow. Receipt printing failure during peak service is a critical UX failure. |
| **Impact**       | 1 -- Printing delay (not data loss, just UX friction)               |
| **Likelihood**   | 5 -- Bluetooth instability is extremely common in real-world use    |
| **Risk Score**   | **5 (Medium)**                                                      |
| **Mitigation**   | 1. Auto-reconnect logic with 3 retries before showing error. 2. Print queue: if print fails, queue and retry. 3. Visual indicator of printer connection status. 4. Support network printers (WiFi/Ethernet) as more reliable alternative. 5. Test with target printers in WiFi-congested environment. 6. Keep Bluetooth connection alive with periodic heartbeat. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

### Business Risks

---

#### R-08: Scope Creep -- Adding Features Before Core Is Solid

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-08                                                                |
| **Category**     | Business                                                            |
| **Description**  | Temptation to add features (online ordering, loyalty, inventory) before the core POS flow is fast, reliable, and tested with real users. Every premature feature steals time from core stability and delays market entry. This is the number one startup killer for POS products. |
| **Impact**       | 3 -- Delayed launch, unstable core, lost pilot customers            |
| **Likelihood**   | 5 -- Very common for technical founders                             |
| **Risk Score**   | **15 (High)**                                                       |
| **Mitigation**   | 1. Strict phase gates: no Phase N+1 work until Phase N success criteria met. 2. "Not yet" list maintained (see doc 20, section D). 3. Weekly self-review: "Am I working on core or on nice-to-have?" 4. Pilot customer feedback as priority compass. 5. If unsure, the answer is "not yet." |
| **Owner**        | CTO / Founder                                                       |
| **Status**       | Open                                                                |

---

#### R-09: UX Complexity Creep

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-09                                                                |
| **Category**     | Business                                                            |
| **Description**  | Each feature adds UI elements. Without discipline, the app becomes cluttered and confusing. Restaurant staff have zero patience for complex UIs -- they need to serve food, not navigate software. A waiter will reject a POS that takes more than 30 seconds to learn. |
| **Impact**       | 3 -- User rejection, failed pilots, negative word-of-mouth          |
| **Likelihood**   | 3 -- Natural tendency as features accumulate                        |
| **Risk Score**   | **9 (Medium)**                                                      |
| **Mitigation**   | 1. "30 second rule": any core flow must be completable in 30 seconds by a new user. 2. Progressive disclosure: hide advanced features behind settings. 3. Test with real waiters every 4 weeks. 4. Measure: time from "open app" to "first order completed" for new users. 5. Feature flags: restaurant enables only what they need. |
| **Owner**        | CTO / UX                                                            |
| **Status**       | Open                                                                |

---

#### R-10: Cash Variance / Theft via Void Abuse

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-10                                                                |
| **Category**     | Business / Operational                                              |
| **Description**  | Staff can steal by creating an order, collecting cash payment, then voiding the order to pocket the money. Excessive discounts and refunds are also theft vectors. Without void tracking and alerts, restaurant owners cannot detect this. |
| **Impact**       | 3 -- Financial loss for restaurant owner, trust issues              |
| **Likelihood**   | 3 -- Cash theft is common in hospitality industry                   |
| **Risk Score**   | **9 (Medium)**                                                      |
| **Mitigation**   | 1. Void requires reason code (mandatory). 2. Void requires manager PIN for orders above threshold. 3. Void rate tracked per staff member. 4. Alert when void rate exceeds 3% of revenue (Layer 5 exception report). 5. Immutable transaction log: voids are recorded, not deleted. 6. Shift close report shows void summary prominently. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-11: License Circumvention (Cracked APK)

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-11                                                                |
| **Category**     | Business                                                            |
| **Description**  | Android APKs can be decompiled and modified to bypass license checks. A cracked version could spread, especially in price-sensitive markets. This undermines revenue and devalues the product. |
| **Impact**       | 4 -- Revenue loss, devalued product                                 |
| **Likelihood**   | 2 -- Possible but requires effort; small market reduces incentive   |
| **Risk Score**   | **8 (Medium)**                                                      |
| **Mitigation**   | 1. License validation requires cloud connectivity (periodic check). 2. Core value is in cloud features (sync, reports, dashboard) -- cracked local-only version has limited appeal. 3. Obfuscate Dart code (Flutter supports this). 4. Server-side feature flags: premium features require valid subscription. 5. Don't over-invest in DRM; focus on making legitimate product valuable. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-12: Single Developer Bus Factor

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-12                                                                |
| **Category**     | Business / Operational                                              |
| **Description**  | With founder/CTO as primary (possibly sole) developer, if they become unavailable (illness, burnout, personal emergency), all development stops. No one else understands the full architecture. |
| **Impact**       | 3 -- Development halted for weeks/months                            |
| **Likelihood**   | 1 -- Low probability in short term, but increases over time         |
| **Risk Score**   | **3 (Low)**                                                         |
| **Mitigation**   | 1. This architecture documentation is mitigation #1: another developer can onboard. 2. Clean code and consistent patterns. 3. Hire second developer by Phase 2 (reduce bus factor to 2). 4. Document all deployment procedures, credentials, and infrastructure. 5. Use managed services to reduce operational knowledge requirements. |
| **Owner**        | Founder                                                             |
| **Status**       | Open                                                                |

---

#### R-13: Payment Terminal Integration Complexity

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-13                                                                |
| **Category**     | Technical / Business                                                |
| **Description**  | Germany (girocard, EC-Karte) and Switzerland (Twint, PostFinance) have different payment ecosystems. Terminal providers (SumUp, Worldline/SIX, Adyen) each have different SDKs and certification requirements. Full payment processing integration could take months per provider. |
| **Impact**       | 4 -- Cannot offer integrated card payments, major competitive gap   |
| **Likelihood**   | 3 -- Integration complexity is well-documented in the industry      |
| **Risk Score**   | **12 (High)**                                                       |
| **Mitigation**   | 1. Phase 1-2: track payment method only (cash vs. card toggle), don't process. 2. Start with one terminal provider per market (SumUp for simplicity). 3. Terminal SDK integration as separate module. 4. Consider SumUp's simple API (Bluetooth terminal + SDK). 5. Defer full payment processing to Phase 8 (kiosk requires it). |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-14: Multi-Tenant Data Isolation Breach

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-14                                                                |
| **Category**     | Technical / Compliance                                              |
| **Description**  | A bug in the cloud backend could allow one tenant to access another tenant's data (orders, revenue, staff info). This would be a severe privacy violation and could destroy trust in the product. |
| **Impact**       | 5 -- Legal liability, reputation destruction, customer loss         |
| **Likelihood**   | 2 -- Possible if tenant isolation is not rigorously enforced        |
| **Risk Score**   | **10 (High)**                                                       |
| **Mitigation**   | 1. PostgreSQL Row-Level Security (RLS) as database-level enforcement. 2. Every API endpoint includes tenant context from JWT, never from request body. 3. Middleware validates tenant on every request. 4. Integration tests: "tenant A cannot see tenant B's data" for every endpoint. 5. Security review before launching multi-tenant cloud. 6. Consider schema-per-tenant for enterprise tier. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open                                                                |

---

#### R-20: Receipt Printer Paper Jam During Peak Hour

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-20                                                                |
| **Category**     | Operational                                                         |
| **Description**  | Thermal printer paper jam or paper roll running out during Friday dinner rush. Staff cannot issue receipts, slowing down table turnover. In Germany, not issuing a receipt is a fiscal violation (Belegausgabepflicht). |
| **Impact**       | 1 -- Brief service disruption, workaround available                 |
| **Likelihood**   | 5 -- Paper jams and empty rolls happen regularly                    |
| **Risk Score**   | **5 (Medium)**                                                      |
| **Mitigation**   | 1. App shows receipt on screen (can show to customer as digital receipt). 2. Email receipt option (capture customer email). 3. Print queue: failed prints retry when printer is ready. 4. "Paper low" notification if printer supports status query. 5. Onboarding training: always have spare paper rolls. |
| **Owner**        | CTO / Support                                                       |
| **Status**       | Open                                                                |

---

#### R-22: Custom Backoffice Out of Sync

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-22                                                                |
| **Category**     | Technical / Business                                                |
| **Description**  | The custom backoffice pulls export data from GastroCore on a schedule. If the pull fails (network issue, API down) or the custom backoffice fails to process the data, accounting entries may be delayed or missing. **NOTE: ERPNext has been removed — risk scope reduced to export API reliability.** |
| **Impact**       | 2 -- Accounting entries delayed; GastroCore operations unaffected   |
| **Likelihood**   | 2 -- Export API is simpler and more reliable than ERPNext bridge    |
| **Risk Score**   | **4 (Low)**                                                         |
| **Mitigation**   | 1. Export API is idempotent: re-requesting same date range always returns same data. 2. Custom backoffice implements its own retry logic. 3. GastroCore data is always the source of truth — re-export is always possible. 4. Reconciliation: custom backoffice compares exported totals with shift reports. |
| **Owner**        | CTO                                                                 |
| **Status**       | Open (reduced from High to Low — ERPNext bridge complexity removed) |

---

#### R-24: Customer Support Burden

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-24                                                                |
| **Category**     | Business / Operational                                              |
| **Description**  | Restaurant POS customers expect immediate support, especially during service hours. A single developer cannot handle development and support simultaneously. Evening/weekend support is expected because that is when restaurants operate. |
| **Impact**       | 2 -- Slow support response, frustrated customers, churn             |
| **Likelihood**   | 4 -- Support load increases linearly with customer count            |
| **Risk Score**   | **8 (Medium)**                                                      |
| **Mitigation**   | 1. Build robust self-service: in-app help, FAQ, troubleshooting guides. 2. WhatsApp support group (async, not phone calls). 3. Limit pilot to 2-3 customers in first 6 months. 4. Build monitoring/alerting to detect issues before customers report them. 5. Hire support person before 10th customer. 6. Prioritize stability over features to reduce support volume. |
| **Owner**        | Founder                                                             |
| **Status**       | Open                                                                |

---

#### R-25: Competitor Releasing Similar Product at Lower Price

| Attribute        | Detail                                                              |
|------------------|---------------------------------------------------------------------|
| **ID**           | R-25                                                                |
| **Category**     | Business                                                            |
| **Description**  | Established competitors (Lightspeed, SumUp, orderbird) or new entrants could release a product with similar features at a lower price point, making GastroCore's pricing uncompetitive. |
| **Impact**       | 2 -- Harder to acquire customers, pricing pressure                  |
| **Likelihood**   | 3 -- POS market is competitive and attracts new entrants            |
| **Risk Score**   | **6 (Medium)**                                                      |
| **Mitigation**   | 1. Compete on simplicity and offline reliability, not price. 2. Focus on underserved niche: small Swiss/German restaurants that find enterprise POS too complex. 3. Transparent pricing (no hidden fees). 4. Build switching costs through data and workflow integration. 5. Speed of iteration as competitive advantage (small team, fast decisions). |
| **Owner**        | Founder                                                             |
| **Status**       | Open                                                                |

---

## 4. Risk Summary by Score

| Score | Level    | Count | Risk IDs                                               |
|-------|----------|-------|--------------------------------------------------------|
| 16-25 | Critical | 2     | R-01 (20), R-04 (16)                                  |
| 10-15 | High     | 9     | R-02 (15), R-03 (12), R-05 (12), R-08 (15), R-13 (12), R-14 (10), R-15 (10), R-17 (15), R-19 (12) |
| 5-9   | Medium   | 12    | R-06 (6), R-07 (8), R-09 (9), R-10 (9), R-11 (8), R-16 (9), R-18 (9), R-20 (5), R-21 (8), R-23 (6), R-24 (8), R-25 (6), R-26 (8), R-27 (5) |
| 1-4   | Low      | 2     | R-12 (3), R-22 (4)                                    |
| Note  | —        | —     | R-06 reduced: 12→6 (ERPNext removed). R-22 reduced: 12→4 (ERPNext removed). |

---

## 5. Top 5 Risks Requiring Immediate Attention

1. **R-01 (Score 20):** Germany fiscal non-compliance. Engage tax advisor and begin Fiskaly spike in Phase 0.
2. **R-04 (Score 16):** Sync conflicts. Design CRDT strategy in Phase 0; implement carefully in Phase 2-3.
3. **R-08 (Score 15):** Scope creep. Maintain discipline; phase gates are non-negotiable.
4. **R-17 (Score 15):** Network reliability. Validate offline-first architecture with real rural testing.
5. **R-02 (Score 15):** Fiskaly API changes. Adapter pattern and version pinning are essential.

---

## 6. Risk Review Schedule

| Review Type          | Frequency  | Participants      | Action                                  |
|----------------------|------------|-------------------|-----------------------------------------|
| Full risk register   | Quarterly  | CTO + team        | Re-score all risks, add new risks       |
| Top 5 risks          | Monthly    | CTO               | Status update, mitigation progress      |
| Critical risks       | Weekly     | CTO               | Check mitigation actions on track       |
| Post-incident review | On event   | CTO + affected    | Add new risk or update existing          |
| Phase gate review    | Per phase  | CTO + team        | Review risks relevant to next phase     |
