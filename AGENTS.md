# CHIC GIFT

## Secret Gift Campaign Platform

### Codex Project Instructions

---

# 1. PROJECT PURPOSE

Build a small production-ready web application for Chic Nail & Beauty called **CHIC GIFT**.

CHIC GIFT is a Secret Gift campaign platform used after customers complete payment in KiotViet.

KiotViet remains the source of truth for:

* invoices;
* payment;
* services;
* revenue;
* customer information.

CHIC GIFT does NOT replace KiotViet.

CHIC GIFT manages only:

**Bill Reference → Eligibility → Unique QR → Secret Gift → Reward → Redemption → Audit → Export**

Primary objectives:

1. Create a fun post-payment customer experience.
2. Encourage customers to return to Chic.
3. Cross-sell additional beauty services.
4. Avoid excessive direct cash discounting.
5. Guarantee one reward per eligible bill.
6. Allow management to track every important action.
7. Allow Admin to create campaigns and prizes without code changes.
8. Keep infrastructure cost as close to zero as practical.
9. Be simple enough to operate at one Chic Nail & Beauty store.
10. Be reusable for future campaigns.

---

# 2. BUSINESS CONTEXT

Current campaign model:

1. Customer completes payment in KiotViet.
2. Staff checks the invoice.
3. Staff enters:

   * Bill Code;
   * Bill Amount.
4. CHIC GIFT validates:

   * Bill Amount >= campaign minimum amount;
   * Bill Code has not previously been registered.
5. If valid:

   * create one Gift Entry;
   * generate a cryptographically strong Gift Token;
   * display a unique QR.
6. Customer scans QR.
7. Customer immediately sees 9 Secret Gift cards.
8. Customer selects one card.
9. Backend atomically assigns one reward.
10. Gift is permanently locked to that reward.
11. Customer sees reward information and redemption conditions.
12. Staff can redeem the reward when the customer returns.

Current initial minimum bill:

**200,000 VND**

Do NOT hard-code this value.

It must come from the active campaign configuration.

---

# 3. IMPORTANT PRODUCT DECISIONS

These decisions are already approved.

Do NOT redesign them unless explicitly requested.

## 3.1 QR strategy

Use:

**One unique QR per eligible bill.**

Do NOT use one common QR.

QR should point to something similar to:

`/g/{giftToken}`

The token must not expose the Bill Code.

---

## 3.2 Customer authentication

Customer does NOT need:

* login;
* phone number;
* OTP;
* email;
* customer account.

The Gift Token is the customer access mechanism.

---

## 3.3 Number of boxes

Customer sees exactly:

**9 Secret Gift cards**

Use a 3 × 3 layout on standard mobile screens.

The number 9 is a UI decision.

It does NOT mean that there must be exactly nine configured prizes.

---

## 3.4 Reward assignment

Do NOT permanently map prizes to individual visual boxes.

The boxes are presentation only.

When the user selects any box:

backend selects the prize according to configured prize weights.

---

## 3.5 One bill, one gift

Fundamental rule:

**1 eligible Bill Code = 1 Gift Entry = maximum 1 Reward**

This rule must be enforced at database level and backend transaction level.

Frontend-only validation is insufficient.

---

# 4. TARGET TECHNOLOGY

Prefer a minimal architecture.

## Frontend

React
Vite
TypeScript

## UI

Use lightweight CSS.

Do not introduce a large UI framework unless clearly justified.

Responsive mobile-first customer interface.

Desktop-first Staff/Admin interface while remaining usable on tablets.

## Hosting

Cloudflare Pages / equivalent static deployment.

## Backend / Database

Supabase

Use:

* PostgreSQL;
* Supabase Auth;
* Row Level Security;
* PostgreSQL functions/RPC and/or Edge Functions when server-side execution is required.

## QR

Generate using an open-source QR library.

Do not use a paid QR service.

## Repository

Git.

Keep database migrations in source control.

---

# 5. COST CONSTRAINT

This campaign is initially expected to operate for approximately one month.

Primary target:

**Infrastructure cost: 0 VND during MVP/campaign where practical.**

Prefer:

* Supabase Free;
* Cloudflare Free;
* existing Chic domain/subdomain;
* open-source dependencies.

Do NOT add paid SaaS products without explicit approval.

Do NOT add:

* SMS;
* Zalo paid APIs;
* paid QR services;
* paid analytics;
* paid authentication providers.

---

# 6. DEPLOYMENT ENVIRONMENT

Development is performed primarily on:

**macOS**

Store operation may use:

**Windows + Chrome/Edge**

Customers may use:

* iPhone;
* Android.

The web application must not depend on any local Windows-only process.

No business data should be stored only on a store computer.

All persistent application data must remain in the cloud database.

---

# 7. APPLICATION ROLES

There are three roles.

## CUSTOMER

Can:

* access a Gift via valid Gift Token;
* select one Secret Gift if not opened;
* view existing Reward;
* view Reward status.

Cannot:

* view Bill database;
* view other Rewards;
* view campaign configuration;
* view probability;
* view staff/admin data.

---

## STAFF

Can:

* sign in;
* create Gift Entry;
* enter Bill Code;
* enter Bill Amount;
* generate/re-display QR;
* search Bill/Reward;
* redeem Reward;
* view operational information required to serve customers.

Cannot:

* change campaigns;
* change prize probabilities;
* modify reward after assignment;
* edit Bill Amount after Gift creation;
* cancel or override records;
* modify Audit Log.

---

## ADMIN

Can:

* manage campaigns;
* manage prizes;
* publish/pause/end campaigns;
* manage staff;
* search and filter Gifts;
* review Rewards;
* review Exceptions;
* export data;
* view Audit Log;
* perform documented overrides.

Admin override must require a reason.

---

# 8. STAFF FLOW

Route example:

`/staff`

Staff signs in.

Main form:

### CHIC SECRET GIFT

Bill Code

`[____________]`

Bill Amount

`[____________]`

Button:

**TẠO QUÀ CHO KHÁCH**

Validation must happen server-side.

---

# 9. BILL VALIDATION

When Staff submits Bill:

## Check 1 — Active Campaign

There must be exactly one applicable Active campaign.

If none:

Do not create Gift.

---

## Check 2 — Minimum Amount

Check:

`billAmount >= activeCampaign.minBill`

If false:

reject request.

Suggested Vietnamese UI:

**Bill này chưa đủ điều kiện nhận quà.**

Show current minimum amount.

---

## Check 3 — Bill uniqueness

Bill Code must be unique within the relevant branch.

Database should enforce a unique constraint.

Preferred future-safe model:

`UNIQUE(branch_id, bill_code)`

Single-store MVP may use one default branch.

---

# 10. DUPLICATE BILL BEHAVIOUR

If Bill Code already exists:

Do NOT create another Gift Entry.

## Existing status ELIGIBLE

Return existing Gift and display existing QR.

## Existing status OPENED

Display existing Reward.

## Existing status REDEEMED

Display existing Reward and:

**Đã sử dụng**

---

# 11. AMOUNT MISMATCH

Example:

Existing record:

HD00123 = 385,000

Staff later submits:

HD00123 = 485,000

Do NOT automatically update Bill Amount.

Record an exception:

`AMOUNT_MISMATCH`

Return a clear error.

Admin must review if correction is needed.

---

# 12. GIFT STATUS

Core statuses:

`ELIGIBLE`

Gift created, QR available, customer has not opened reward.

`OPENED`

Customer has received Reward.

`REDEEMED`

Reward has been used.

`EXPIRED`

Reward expired.

`CANCELLED`

Gift cancelled through an Admin action.

Use explicit enums/constants.

Avoid arbitrary string values throughout the application.

---

# 13. UNIQUE TOKEN

Gift Token requirements:

* generated server-side;
* cryptographically strong;
* difficult to guess;
* not sequential;
* never based directly on Bill Code;
* unique database constraint.

Do not expose internal database IDs to customers.

---

# 14. STAFF QR SCREEN

After successful Gift creation:

Display:

### QUÀ ĐÃ SẴN SÀNG 🎁

Bill Code
Bill Amount

QR

Text:

**Mời khách quét để chọn quà**

Actions:

* Show QR;
* copy Gift link;
* create next Bill.

---

# 15. CUSTOMER ROUTE

Example:

`/g/{giftToken}`

Resolve token server-side.

If invalid:

show friendly invalid Gift page.

---

# 16. CUSTOMER EXPERIENCE

If Gift status is:

## ELIGIBLE

Show:

### CHIC SECRET GIFT

**Hôm nay nàng có quà 🎀**

Suggested copy:

**9 ô đang giấu quà. Nàng chọn đại một ô có duyên đi 😌**

Display nine Secret Gift cards.

---

## OPENED

Do NOT display Secret Gift selection.

Display existing Reward.

---

## REDEEMED

Display existing Reward plus:

**✓ Quà đã được sử dụng**

---

## EXPIRED

Display Reward plus:

**Quà đã hết hạn sử dụng**

---

## CANCELLED

Display appropriate unavailable message.

---

# 17. CUSTOMER VISUAL DIRECTION

Brand feel:

**Beauty Boutique**

Preferred palette:

* warm cream;
* beige;
* mocha;
* dark chocolate;
* champagne accent.

Avoid:

* casino aesthetic;
* red/yellow jackpot visuals;
* spinning wheel;
* childish game UI;
* excessive gradients;
* excessive confetti;
* visually noisy promotional style.

Preferred Secret Gift representation:

**9 elegant envelopes/cards**

rather than traditional cartoon gift boxes.

Animation:

short and lightweight.

Approximately 1–1.5 seconds is sufficient.

Customer UX must prioritize fast mobile loading.

---

# 18. OPEN GIFT TRANSACTION

This is a critical system operation.

When Customer selects any Gift card:

Do NOT select prize in frontend.

Execute server-side atomic logic.

Required conceptual sequence:

1. Locate Gift Entry by token.
2. Lock appropriate Gift record.
3. Confirm status == ELIGIBLE.
4. Determine available prizes.
5. Exclude inactive/out-of-stock prizes.
6. Randomly select Prize using Weight.
7. Create Reward.
8. Save Prize Snapshot.
9. Increment Prize issued quantity atomically.
10. Set Gift status = OPENED.
11. Set opened_at.
12. Commit.
13. Return Reward.

If another request arrives simultaneously after locking:

return the already-created Reward.

Never create another Reward.

---

# 19. CONCURRENCY REQUIREMENT

The following scenario must work:

Device A and Device B scan the same QR.

Both select a gift at nearly the same time.

Expected:

**exactly one Reward exists.**

Both devices eventually display the same Reward.

This must be covered by automated or integration tests where practical.

---

# 20. REFRESH REQUIREMENT

After Reward assignment:

Customer refreshes browser.

Expected:

same Reward.

No reroll.

---

# 21. PRIZE MODEL

Admin can create Prize definitions.

Supported MVP types:

`CASH_VOUCHER`

`PERCENT_DISCOUNT`

`FREE_SERVICE`

`SERVICE_DISCOUNT`

`SERVICE_UPGRADE`

`CUSTOM_REWARD`

Prize fields:

* name;
* type;
* customer_description;
* customer_value;
* estimated_chic_cost;
* minimum_spend;
* applicable_service;
* expiry_days;
* weight;
* max_quantity;
* issued_quantity;
* active;
* fallback flag if required.

---

# 22. PRIZE WEIGHT

Admin configures Weight.

Do NOT require weights to total 100.

Example:

25
20
15
10
5

Backend normalizes them automatically.

Probability configuration must never be exposed to Customer.

---

# 23. PRIZE INVENTORY

Admin can set:

`max_quantity`

Example:

Voucher 50K

Maximum Quantity = 20

After issued quantity reaches 20:

Prize becomes unavailable for future random selections.

Do NOT exceed max quantity due to concurrent requests.

Inventory update must be part of the same transaction as Reward creation.

---

# 24. FALLBACK PRIZE

System must always have a safe result when a campaign is active.

Prefer requiring at least one active fallback or sufficiently available Prize.

Publishing a campaign with no valid Prize should fail validation.

---

# 25. ESTIMATED CHIC COST

Separate:

**Customer Value**

from:

**Estimated Chic Cost**

Example:

Free Nail Art 2 fingers

Customer Value: 30,000
Estimated Chic Cost: 7,000

Use this data for Admin reporting.

---

# 26. CAMPAIGN / PROMOTION MANAGER

Admin route:

`/admin/campaigns`

Admin can create:

**Secret Gift Campaigns**

Do NOT build a generic promotion engine supporting every possible promotion type.

Keep scope limited to Secret Gift Campaign.

---

# 27. CAMPAIGN FIELDS

Minimum fields:

* Campaign Name;
* Start Date;
* End Date;
* Minimum Bill;
* Gift Open Deadline if enabled;
* Customer Headline;
* Customer Description;
* Terms;
* status;
* created_by;
* created_at.

---

# 28. CAMPAIGN STATUS

Use lifecycle:

`DRAFT`

`SCHEDULED`

`ACTIVE`

`PAUSED`

`ENDED`

`ARCHIVED`

---

# 29. CAMPAIGN RULE

For MVP:

**one branch should have only one Active Secret Gift Campaign at a time.**

Prevent overlapping Active campaigns unless explicitly changed later.

---

# 30. CAMPAIGN VERSIONING

Critical business requirement.

Do not allow edits to historical issued rewards.

When a Campaign has started issuing Gifts:

important campaign/prize configuration must be immutable for those existing Gifts.

Recommended model:

Campaign
→ Campaign Version

Each Gift Entry references the exact Campaign Version used when it was created.

If Admin wants meaningful changes:

clone/create a new version.

Existing Gifts stay linked to old version.

New Gifts use the new version.

---

# 31. REWARD SNAPSHOT

When Reward is created, save a snapshot of customer-facing Prize conditions.

Snapshot should include at least:

* Prize Name;
* customer description;
* customer value;
* minimum spend;
* applicable service;
* expiry rule/value.

Why:

If Admin changes a Prize template later, the customer's already-issued Reward must not change.

---

# 32. REWARD CODE

Generate a user-friendly Reward Code.

Example:

`CHIC-X82K9`

It must be unique.

Staff can search by:

* Bill Code;
* Reward Code.

---

# 33. REWARD EXPIRY

Reward should store an absolute:

`expires_at`

Calculate at Reward issuance time.

Do not calculate dynamically on every page load from the current Prize template.

---

# 34. REDEMPTION

Staff opens:

`/staff/redeem`

Search:

Bill Code or Reward Code.

Display:

* Reward;
* status;
* expiry;
* minimum spend;
* applicable service.

Staff clicks:

**REDEEM**

Server validates:

* Reward exists;
* status is OPENED;
* not expired.

Then atomically:

OPENED → REDEEMED

Store:

* redeemed_at;
* redeemed_by.

Repeated redemption attempts must fail safely.

---

# 35. ADMIN OVERRIDE

Admin may handle exceptional operational cases.

Examples:

* staff entered incorrect Bill;
* customer complaint;
* accidental redemption;
* exceptional expiry approval.

Every override requires:

`reason`

No silent override.

Every override generates Audit Log.

---

# 36. AUDIT LOG

Audit is mandatory.

Audit Log should be append-only from application perspective.

Important actions:

`LOGIN`

`CREATE_GIFT`

`DUPLICATE_ATTEMPT`

`AMOUNT_MISMATCH`

`GENERATE_QR`

`OPEN_GIFT`

`REDEEM_GIFT`

`CREATE_CAMPAIGN`

`EDIT_CAMPAIGN`

`PUBLISH_CAMPAIGN`

`PAUSE_CAMPAIGN`

`END_CAMPAIGN`

`CREATE_PRIZE`

`EDIT_PRIZE`

`ADMIN_OVERRIDE`

`CANCEL_GIFT`

Audit fields:

* id;
* action;
* actor_id if applicable;
* entity_type;
* entity_id;
* bill_code when useful;
* old_data JSON;
* new_data JSON;
* reason;
* created_at;
* metadata JSON.

Do not provide Edit/Delete Audit buttons.

---

# 37. ADMIN DASHBOARD

Keep dashboard simple.

Display useful operational metrics only.

Suggested:

* Gifts Created;
* Gifts Opened;
* Not Opened;
* Redeemed;
* Expired;
* Duplicate Attempts;
* Amount Mismatch;
* Total qualifying Bill Amount;
* Estimated Reward Cost.

Avoid over-engineered BI.

---

# 38. CAMPAIGN PERFORMANCE

Display:

* Total Gifts Created;
* Open Rate;
* Rewards Issued;
* Redeem Rate;
* Total Bill Value;
* Estimated Reward Cost;
* Average Reward Cost.

---

# 39. PRIZE PERFORMANCE

For each Prize show:

* Issued;
* Redeemed;
* Redemption Rate;
* Estimated Issued Cost;
* Estimated Redeemed Cost.

---

# 40. BILL MANAGEMENT

Admin table should support:

* Bill Code;
* Amount;
* Campaign;
* Reward;
* Status;
* Created By;
* Created At;
* Opened At;
* Redeemed At;
* Redeemed By.

Search and filter:

* Bill Code;
* Reward Code;
* Date;
* Staff;
* Status;
* Campaign;
* Prize;
* Exceptions.

---

# 41. EXCEPTIONS

Provide an Admin Exceptions view.

Important exception types:

* duplicate attempts;
* amount mismatch;
* cancelled Gift;
* Admin override;
* expired redemption attempt;
* inventory issue;
* invalid campaign state.

Do not implement speculative fraud detection.

Keep Exception logic deterministic and explainable.

---

# 42. EXPORT

Admin must be able to export operational data.

MVP format:

**CSV**

CSV should contain:

* Bill Code;
* Bill Amount;
* Campaign;
* Campaign Version;
* Created At;
* Created By;
* Gift Status;
* Prize;
* Customer Value;
* Estimated Chic Cost;
* Opened At;
* Expiry;
* Redeemed At;
* Redeemed By.

Also support:

**Audit CSV Export**

Do not add XLSX dependency in the first implementation unless explicitly requested.

---

# 43. KIOTVIET RECONCILIATION

MVP is NOT integrated with KiotViet API.

Staff manually enters:

* Bill Code;
* Bill Amount.

Therefore CHIC GIFT cannot guarantee that the value entered matches KiotViet.

Mitigation:

* individual Staff accounts;
* Audit Logs;
* Exceptions;
* regular CSV export and reconciliation.

Do not pretend that manual input can be automatically verified.

---

# 44. FUTURE PHASE – KIOTVIET IMPORT

Not MVP.

Potential later feature:

Admin uploads KiotViet export file.

System compares:

`Bill Code + Amount`

against CHIC GIFT.

Possible statuses:

`MATCH`

`AMOUNT_MISMATCH`

`MISSING_IN_CHIC_GIFT`

`NOT_FOUND_IN_KIOTVIET`

Do NOT build until an actual KiotViet export sample is supplied.

---

# 45. CUSTOMER DATA MINIMIZATION

MVP must not collect unnecessary PII.

Do not collect:

* Customer Name;
* Phone;
* Email;
* Date of Birth.

unless explicitly added later.

This reduces:

* security risk;
* privacy scope;
* implementation complexity.

---

# 46. SECURITY REQUIREMENTS

Mandatory:

* Supabase Auth for Staff/Admin;
* Row Level Security;
* server-side Prize selection;
* no Service Role key exposed to browser;
* no database secret committed to Git;
* environment variables;
* role authorization enforced server-side;
* Gift Tokens sufficiently random;
* customer access limited to exact Gift associated with Token.

Frontend hiding is not authorization.

---

# 47. DATABASE SCHEMA – RECOMMENDED

## branches

id
name
active
created_at

Create one default Chic branch for MVP.

---

## staff_profiles

id
auth_user_id
name
role
active
created_at

Roles:

STAFF
ADMIN

---

## campaigns

id
branch_id
name
status
start_at
end_at
created_by
created_at

---

## campaign_versions

id
campaign_id
version_number
min_bill
gift_open_deadline_hours nullable
headline
description
terms
published_at
created_at

---

## prizes

id
campaign_version_id
name
type
customer_description
customer_value
estimated_cost
minimum_spend
applicable_service
expiry_days
weight
max_quantity nullable
issued_quantity
is_fallback
active
created_at

---

## gift_entries

id
branch_id
bill_code
bill_amount
campaign_version_id
gift_token
status
created_by
created_at
opened_at
cancelled_at nullable

Unique:

`branch_id + bill_code`

Unique:

`gift_token`

---

## rewards

id
gift_entry_id
prize_id
reward_code
prize_snapshot JSONB
expires_at
created_at
redeemed_at nullable
redeemed_by nullable

One Reward per Gift:

`UNIQUE(gift_entry_id)`

Unique:

`reward_code`

---

## audit_logs

id
action
actor_id nullable
entity_type
entity_id
old_data JSONB nullable
new_data JSONB nullable
reason nullable
metadata JSONB nullable
created_at

---

# 48. DATABASE MIGRATIONS

Never manually depend on production database state.

Keep SQL migrations under version control.

Recommended:

`supabase/migrations/`

Schema changes must be reproducible.

---

# 49. CODE STRUCTURE

Prefer clear feature boundaries.

Example:

src/
components/
features/
auth/
gifts/
rewards/
campaigns/
prizes/
admin/
audit/
export/
pages/
services/
lib/
types/

Avoid one huge component.

Avoid premature abstraction.

---

# 50. TYPE SAFETY

Use TypeScript strictly enough to catch common mistakes.

Prefer domain types/enums for:

* GiftStatus;
* CampaignStatus;
* PrizeType;
* UserRole;
* AuditAction.

Do not spread raw magic strings throughout components.

---

# 51. ERROR HANDLING

Customer-facing errors:

friendly and minimal.

Admin/Staff errors:

clear enough to take action.

Do not expose:

* database stack traces;
* internal SQL;
* service keys;
* sensitive configuration.

---

# 52. TESTING PRIORITY

Do not prioritize animation tests over business logic.

Highest priority tests:

1. Minimum Bill validation.
2. Duplicate Bill protection.
3. Amount mismatch.
4. One Gift Token per Bill.
5. One Reward per Gift.
6. Concurrent opening.
7. Refresh/re-open.
8. Prize max quantity.
9. Redeem only once.
10. Expiry.
11. Authorization.
12. Campaign version immutability.

---

# 53. REQUIRED ACCEPTANCE CRITERIA

## AC01

Bill below Campaign Minimum cannot create Gift.

## AC02

Duplicate Bill Code cannot create another Gift.

## AC03

Duplicate Bill with different Amount is flagged.

## AC04

Valid Bill creates exactly one Gift Token.

## AC05

QR opens directly to nine Secret Gift cards.

## AC06

One Bill receives exactly one Reward.

## AC07

Double-click does not create two Rewards.

## AC08

Concurrent devices cannot create different Rewards.

## AC09

Refresh never rerolls Reward.

## AC10

Scanning QR after opening displays existing Reward.

## AC11

Redeemed Reward cannot be redeemed again.

## AC12

Prize cannot exceed Max Quantity.

## AC13

Existing Reward conditions cannot be changed through later Prize edits.

## AC14

Staff cannot access Admin configuration.

## AC15

Customer cannot browse application data.

## AC16

Admin can export operational CSV.

## AC17

Important operations are Audit Logged.

## AC18

Admin override requires Reason.

---

# 54. OUT OF SCOPE

Do NOT build unless explicitly requested:

* KiotViet API integration;
* SMS;
* OTP;
* Zalo API;
* mobile apps;
* loyalty points;
* memberships;
* CRM;
* customer accounts;
* AI features;
* referral system;
* birthday automation;
* generic promotion engine;
* complex BI;
* payment processing;
* multiple overlapping campaigns;
* complex multi-branch permissions.

---

# 55. MVP DEVELOPMENT PHASES

Do not attempt to implement the entire application in one uncontrolled change.

## PHASE 0 — Environment & Architecture

Before writing product code:

1. inspect local environment;
2. confirm Node/npm versions;
3. confirm project directory;
4. initialize Git;
5. create Vite React TypeScript project;
6. define environment variable strategy;
7. document architecture;
8. create implementation checklist.

Do not deploy yet.

---

## PHASE 1 — Database Foundation

Implement:

* Supabase structure;
* migrations;
* branches;
* staff profiles;
* campaigns;
* campaign versions;
* prizes;
* Gift Entries;
* Rewards;
* Audit Logs;
* enums;
* constraints;
* RLS.

Create seed data for development.

Add one Admin and one Staff path/documentation.

Stop and validate schema before proceeding.

---

## PHASE 2 — Staff Gift Creation

Implement:

* login;
* Staff authorization;
* Create Gift page;
* Active Campaign resolution;
* Minimum Bill validation;
* duplicate protection;
* amount mismatch;
* Gift Token;
* QR screen;
* Audit.

Test.

---

## PHASE 3 — Customer Gift Experience

Implement:

* Gift Token resolution;
* Customer mobile UI;
* 9 cards;
* open Gift atomic server logic;
* weighted Prize selection;
* inventory;
* Reward Snapshot;
* Reward Reveal;
* repeat scan.

Test concurrency before moving on.

---

## PHASE 4 — Redemption

Implement:

* Staff search;
* Reward details;
* expiry;
* redeem;
* duplicate redemption protection;
* Audit.

---

## PHASE 5 — Admin Campaign Management

Implement:

* Campaign List;
* Create Draft;
* Prize configuration;
* Weight;
* Max Quantity;
* Estimated Cost;
* Preview;
* Publish;
* Pause;
* End;
* Campaign versioning.

Test historical integrity.

---

## PHASE 6 — Administration

Implement:

* dashboard;
* Bill table;
* Reward table;
* filters;
* Exceptions;
* Audit viewer;
* CSV export;
* Staff management;
* Admin Override.

---

## PHASE 7 — Visual Polish

Implement Chic visual style.

Prioritize Customer screen.

Keep Staff/Admin functional and clean.

Test:

* macOS Chrome;
* Windows Chrome/Edge;
* iPhone Safari;
* Android Chrome.

---

## PHASE 8 — Production Readiness

Before production:

* run full tests;
* review RLS;
* check secrets;
* test invalid tokens;
* test race condition;
* test expired Reward;
* test duplicate redemption;
* create backup/export procedure;
* configure domain;
* deploy;
* perform UAT with test Bills.

---

# 56. CODEX WORKING RULES

When working on this repository:

1. Read this AGENTS.md before making architectural decisions.
2. Do not change approved business rules without explaining the conflict first.
3. Do not expand scope automatically.
4. Prefer the simplest implementation that meets acceptance criteria.
5. Never sacrifice database integrity for frontend convenience.
6. Before making schema changes, review existing migrations.
7. Never expose secrets.
8. Do not assume client-side checks are security.
9. Run relevant tests after every meaningful change.
10. Report:

* files changed;
* tests run;
* test results;
* unresolved risks.

11. If a requirement conflicts with existing implementation, identify the conflict before silently rewriting it.
12. Avoid large unrelated refactors during feature work.
13. Prefer deterministic rules over speculative fraud detection.
14. Preserve historical campaign/reward data.
15. Optimize for maintainability by a non-full-time developer.

---

# 57. CODEX RESPONSE STYLE

For implementation tasks:

Start with a short inspection summary.

Then provide:

**What I found**

**What I will change**

Implement the change.

After implementation provide:

**Files changed**

**Validation**

**Remaining risks**

Do not produce long generic tutorials unless requested.

---

# 58. BUSINESS PRIORITY ORDER

If compromises are necessary, prioritize:

1. Correct one-Bill-one-Reward behaviour.
2. Security.
3. Auditability.
4. Operational simplicity.
5. Campaign configurability.
6. Customer experience.
7. Analytics.
8. Visual effects.

Never prioritize animation over transactional correctness.

---

# 59. PRODUCTION OPERATING MODEL

KiotViet:

Customer payment.

↓

Staff verifies invoice.

↓

CHIC GIFT Staff:

Bill Code + Amount.

↓

Validate.

↓

Generate QR.

↓

Customer:

Scan.

↓

9 Secret Gifts.

↓

Open.

↓

Reward.

↓

Later:

Staff Redeem.

↓

Admin:

Dashboard + Audit + Export.

---

# 60. FINAL PRODUCT PRINCIPLE

CHIC GIFT should remain:

**a small, reliable Secret Gift Campaign Platform**

not:

**a generic CRM or enterprise Promotion Engine.**

The application must be cheap to operate, easy for Chic staff to use, easy for Admin to control, auditable, secure, and reusable for future Secret Gift campaigns.
# ADDITIONAL PROJECT RULE — MULTI-DISCIPLINE PROMPT REVIEW

Before providing any Codex prompt for this project, the prompt must be reviewed from all relevant professional perspectives.

The purpose is to avoid prompts that are technically correct but operationally weak, visually poor, insecure, difficult to maintain, or inconsistent with Chic Nail & Beauty business goals.

For each Codex task, review the intended prompt against the relevant roles below.

## REQUIRED REVIEW ROLES

### 1. PRODUCT OWNER / BUSINESS OWNER

Review:

* Does this feature solve the actual Chic operational need?
* Does it create unnecessary scope?
* Does it support the campaign objective?
* Is the workflow realistic for store staff?
* Does it create unnecessary cost?
* Can Admin operate it without developer support?
* Does it preserve the principle that KiotViet remains the source of truth for sales?

Reject unnecessary functionality even if it is technically attractive.

---

### 2. SOFTWARE ARCHITECT / TECH LEAD

Review:

* Is the implementation architecture appropriate for the current scale?
* Is there a simpler approach?
* Are we introducing unnecessary libraries, services, backend layers, or abstractions?
* Does the design work with React + Vite + TypeScript + Supabase + Cloudflare?
* Does the feature preserve maintainability?
* Are database constraints correct?
* Are race conditions handled?
* Does the implementation preserve historical data?

Prefer:

simple, deterministic, maintainable solutions.

Avoid:

over-engineering.

---

### 3. BACKEND / DATABASE ENGINEER

Review:

* Can duplicate Bill Codes occur?
* Can two Rewards be created concurrently?
* Are database constraints enforcing business rules?
* Is the operation atomic?
* Are transactions required?
* Can inventory exceed max quantity?
* Can Reward state become inconsistent?
* Is campaign versioning preserved?
* Is Audit data reliable?

Business-critical rules must not rely only on frontend validation.

---

### 4. SECURITY ENGINEER

Review:

* Is any secret exposed?
* Is authorization enforced server-side?
* Are Supabase RLS policies correct?
* Can Customer access another Gift or Reward?
* Can Staff access Admin functions?
* Can users manipulate Prize probability?
* Can users directly update Reward status?
* Are tokens sufficiently random?
* Are inputs validated?
* Does the feature unnecessarily collect personal data?

Apply data minimization.

Do not collect customer PII unless explicitly approved.

---

### 5. UX / UI DESIGNER

Review:

* Is the flow understandable without explanation?
* Is the Customer journey fast enough?
* Are there unnecessary steps?
* Is the mobile layout usable?
* Is the CTA clear?
* Does the screen follow Chic Nail & Beauty visual direction?
* Does the design feel premium, friendly, and suitable for a beauty boutique?
* Are error messages understandable?
* Is Staff UI optimized for speed rather than decoration?
* Is Admin UI optimized for control and readability?

Customer UI priority:

visual experience.

Staff UI priority:

speed.

Admin UI priority:

clarity and control.

---

### 6. RETAIL / STORE OPERATIONS SPECIALIST

Review:

* Can a busy employee operate this while serving customers?
* How many clicks are required?
* What happens when the store is busy?
* What happens if Staff enters the wrong Bill?
* What happens if Customer does not scan immediately?
* Can Staff easily recover an existing QR?
* Can Staff find a Reward quickly when Customer returns?
* Are operational exceptions clearly handled?

Prefer workflows that require minimal training.

---

### 7. MARKETING / CRM SPECIALIST

Review:

* Does this feature encourage repeat visits?
* Can rewards drive cross-sell?
* Are promotions configurable without developer intervention?
* Are prize rules flexible enough?
* Can Admin control cost?
* Can campaign performance be measured?
* Does the Customer message create a clear conversion action?
* Is there an appropriate booking CTA?

Do not optimize only for “fun”.

The system should support:

repeat booking + revenue.

---

### 8. FINANCE / COST CONTROL

Review when the feature affects campaigns, prizes, promotions, or reporting.

Check:

* Estimated Chic Cost.
* Maximum Prize Quantity.
* Expected reward cost.
* Potential uncontrolled discount exposure.
* Campaign budget visibility.
* Whether reward rules can accidentally create excessive cost.
* Whether reporting distinguishes Customer Value from actual Chic Cost.

The system should allow Chic to control campaign cost before launch.

---

### 9. QA / TEST ENGINEER

Review:

* What is the happy path?
* What are the edge cases?
* What can fail?
* What happens on refresh?
* What happens with duplicate clicks?
* What happens on two devices?
* What happens with expired Rewards?
* What happens with inactive campaigns?
* What happens when Prize inventory is exhausted?
* What permissions need testing?
* What regression risk exists?

Every important business feature should have acceptance criteria before implementation.

---

# PROMPT OPTIMIZATION PROCESS

Before giving a Codex implementation prompt:

## STEP 1 — Identify affected disciplines

Not every task requires all roles.

Example:

A Customer Gift animation task may require:

* Product;
* UX/UI;
* Frontend Technical;
* QA;
* Performance.

A database concurrency task may require:

* Software Architect;
* Backend;
* Database;
* Security;
* QA.

A Promotion Manager task may require:

* Product;
* Marketing;
* Finance;
* UX/UI;
* Backend;
* Security;
* QA.

---

## STEP 2 — Challenge the requested feature

Before instructing Codex to build it, ask:

* Is the feature actually necessary?
* Can the same objective be achieved more simply?
* Will this increase operating cost?
* Will it make Staff workflow harder?
* Will it introduce security risk?
* Does it belong in the MVP?
* Does it contradict existing approved business rules?

If a better alternative exists, use the better alternative in the final Codex prompt and explain the material trade-off to the project owner.

---

## STEP 3 — Define boundaries

Every Codex prompt should clearly state:

### IN SCOPE

What Codex is expected to implement.

### OUT OF SCOPE

What Codex must not modify or add.

This prevents scope expansion.

---

## STEP 4 — Define invariants

Where relevant, explicitly state rules that must remain true.

Examples:

* one Bill = one Gift;
* one Gift = one Reward;
* no reroll;
* Staff cannot access Admin;
* Customer cannot access Bill database;
* Prize inventory cannot exceed maximum;
* existing Reward terms cannot change retrospectively.

---

## STEP 5 — Define acceptance criteria

Every implementation prompt should include measurable acceptance criteria.

Avoid vague requirements such as:

“Make it secure.”

Prefer:

* Staff role receives 403/authorization failure when calling Admin-only action.
* Customer token can return only its own Gift.
* Duplicate Bill insert fails safely.
* Two simultaneous open requests result in one Reward row.

---

## STEP 6 — Require inspection before modification

Codex must first inspect relevant:

* files;
* existing code;
* database migrations;
* tests;
* architecture.

It must not assume the implementation state.

Prompts should normally instruct Codex to report:

### What I found

before changing code.

---

## STEP 7 — Require minimal change

Codex should modify only what is required for the current task.

Do not allow unrelated:

* dependency changes;
* framework changes;
* refactoring;
* visual redesign;
* schema redesign.

Unless technically necessary and explicitly justified.

---

## STEP 8 — Require validation

Every Codex task must state the required validation.

Depending on task:

* typecheck;
* lint;
* unit tests;
* integration tests;
* database tests;
* build;
* manual browser validation;
* concurrency test;
* security/RLS test.

---

## STEP 9 — Require post-implementation report

Every Codex implementation response should end with:

### Files changed

### What changed

### Validation performed

### Acceptance criteria result

### Remaining risks

### Recommended next task

Do not accept “done” without validation evidence.

---

# FINAL CODEX PROMPT QUALITY RULE

Do not give Codex the user's raw request directly when the task is material.

Convert it into an optimized engineering task first.

The final prompt must:

1. preserve the user's business intent;
2. reflect current CHIC GIFT architecture;
3. include relevant professional critique;
4. eliminate unnecessary scope;
5. state security and data integrity constraints;
6. include UX/operational constraints where applicable;
7. define exact acceptance criteria;
8. specify testing expectations;
9. prevent unrelated changes;
10. request a structured implementation report.

---

# PROJECT OWNER COMMUNICATION

Before giving the final Codex prompt to the project owner, provide a concise summary when there is a material design decision:

**Professional review conclusion**

Explain:

* what was challenged;
* what was retained;
* what was changed;
* why the final approach is better for Chic.

Then provide only the optimized Codex prompt.

Do not provide multiple weak prompts when one strong prompt can be produced.

---

# CORE PRINCIPLE

For CHIC GIFT:

**The best prompt is not the most detailed prompt.**

The best prompt is the one that gives Codex:

* enough context to make the correct change;
* clear boundaries;
* measurable acceptance criteria;
* no unnecessary freedom to change approved architecture.

Every Codex prompt should optimize for:

**Business fit + Technical correctness + Security + UX + Operational simplicity + Cost control + Testability.**
