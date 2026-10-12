# QSS Lead System — AI Handoff Document

**Project:** Quick Short Sales (Jack Watlington) lead capture and pipeline  
**Domain:** quickshortsales.net  
**Prepared for:** AI model managing the 2nd brain / replication reference  
**Status as of handoff:** Core security migration complete; table lockdown in place; dashboard auth deployed; notify handler ZZTEST override pending

---

## 1. What This System Does

A real estate short-sale lead system for Jack Watlington (Fidelity Realty Advisors, South Florida). The flow:

1. Jack uploads Property Radar CSV exports into Supabase via the Aiphorism client portal admin
2. Each property gets a unique UUID as its record ID
3. Postcards are mailed to homeowners (manually via Lob.com for now)
4. Each postcard has a QR code linking to `quickshortsales.net/?src=qr&id=<property-uuid>`
5. When a homeowner scans the QR, the landing page fires an RPC that marks them warm, increments scan count, and sends a notification email to Jack
6. When a homeowner submits the guide download form, another RPC marks them hot and records the submission
7. Jack and Fidel monitor the pipeline via a private dashboard at `quickshortsales.net/dashboard/`

---

## 2. Repositories

| Repo | GitHub | Purpose |
|------|--------|---------|
| jr-leads-page | `rookstack/jr-leads-page` | Public site + dashboard (deployed to GitHub Pages) |
| aiphorism-client-portal | `rookstack/aiphorism-client-portal` | Admin UI for lead import + `/api/notify` handler |

### Deployment
- **quickshortsales.net** → GitHub Pages, CNAME in `jr-leads-page` repo root
- Pushes to `main` deploy automatically (no build step — static HTML)
- **aiphorism-client-portal.vercel.app** → Vercel, auto-deploys from its `main` branch

---

## 3. Supabase

- **Project:** `uebyzgrsaylfexldhccu`
- **Dashboard:** https://supabase.com/dashboard/project/uebyzgrsaylfexldhccu
- **Schema:** `jr_leads` (all tables and RPCs live here)
- **Anon key:** Public by design — in page source. The key itself does not need rotating.
- **PostgREST:** `jr_leads` schema must be listed in Settings → API → Extra schemas

### Tables

#### `jr_leads.lists`
Tracks each Property Radar CSV export as a named batch.
```
id           UUID PK
name         TEXT         -- e.g. "High Distress March 2026"
description  TEXT
source       TEXT         -- default 'property_radar'
imported_at  TIMESTAMPTZ
record_count INTEGER
```

#### `jr_leads.properties`
434 homeowner leads. Core table. Full schema in `sql/schema-update-001.sql`.
Key fields:
```
id                UUID PK
list_id           UUID FK → lists
primary_first     TEXT    -- owner first name (used in mailers)
primary_last      TEXT
address, city, state, zip
distress_score    INTEGER (0–100)
est_equity        INTEGER (can be negative)
est_value         INTEGER
lead_status       VARCHAR(32)  -- 'unassigned','warm','hot'
is_warm, is_hot   BOOLEAN
warm_at, hot_at   TIMESTAMPTZ
qr_scan_count     INTEGER
qr_scanned_at     TIMESTAMPTZ
stage             INTEGER (1–3)
dropped           BOOLEAN
phone, email      TEXT (unlocked via Property Radar credits)
prp_validated     BOOLEAN  -- owner identity verified via RPR
prp_owner_match   BOOLEAN
```

#### `jr_leads.form_submissions`
Audit log of all form completions. Written by RPCs server-side.
```
id           UUID PK
property_id  UUID FK → properties (nullable for direct/ad submissions)
qr_code      TEXT
form_type    TEXT
first_name, last_name, phone, email, full_address
submitted_at TIMESTAMPTZ
```

#### `jr_leads.guide_leads`
Captures form submissions from visitors who arrived directly (no QR / no property record).
Written by `guide_submit_direct` RPC.

---

## 4. The Five Security-Definer RPCs

All public pages talk ONLY through these — no direct table access for anon.

**Call pattern for all RPCs:**
```
POST {SUPABASE_URL}/rest/v1/rpc/<function_name>
Headers:
  apikey: <anon key>
  Authorization: Bearer <anon key>
  Content-Type: application/json
  Content-Profile: jr_leads
  Accept-Profile: jr_leads
Body: JSON of named args
```

| Function | Args | Returns | What it does |
|----------|------|---------|--------------|
| `qr_scan` | `p_id` | `[{first, last, address, city, state, scan_count, first_scan}]` | Increments scan count, sets warm (never downgrades hot), sets timestamps + lead_source. Empty array if ID not found. |
| `guide_prefill` | `p_id` | `[{first, last, address, city, state, zip}]` | Read-only property lookup for gate form pre-population. |
| `mark_hot` | `p_id` | void | Marks property hot. Called on hot-lead form submit from landing page. |
| `guide_submit_qr` | `p_id, p_name, p_email, p_phone, p_address, p_city, p_state, p_zip` | int (new scan count, null if ID not found) | Updates property (email, phone, hot status), writes form_submissions row. |
| `guide_submit_direct` | `p_name, p_email, p_phone, p_address, p_city, p_state, p_zip, p_source` | void | Inserts guide_leads + form_submissions. `p_source`: `'ad'` or `'direct'`. |

SQL migrations are in `sql/` in the repo. RPC definitions are in Supabase only (not in the repo) — verify in the SQL editor.

---

## 5. Public Site Pages (quickshortsales.net)

| File | Path | Purpose |
|------|------|---------|
| `index.html` | `/` | Landing page. QR scan tracking + hot-lead form. UUID guard on `id` param. |
| `short-sale-guide.html` | `/short-sale-guide.html` | Lead gate → 5-page guide PDF. Prefill, QR submit, direct submit. |
| `privacy-policy.html` | `/privacy-policy.html` | Legal |
| `postcard-stage1/2/3.html` | `/postcard-*.html` | Print-ready postcard templates (HTML → PDF) |
| `stage1/2/3.html` | `/stage1.html` etc | Stage variants |
| `banners.html` | — | Ad banner assets |

### Key behaviors
- **UUID guard everywhere:** `id` param is regex-validated (`/^[0-9a-f]{8}-...-[0-9a-f]{12}$/i`) before any RPC call. Junk query strings never hit the DB.
- **Guide link carries params:** `short-sale-guide.html?src=qr&id=<uuid>` for QR visitors; `?src=direct` for organic.
- **Notify fires non-blocking** after each RPC — never blocks the user experience.
- **Guide opens on RPC failure** — user always gets the guide even if the DB call fails.

---

## 6. Dashboard (quickshortsales.net/dashboard/)

File: `dashboard/index.html`

**Auth:** Supabase Auth magic link (`signInWithOtp`, `shouldCreateUser: false`)  
**Authorized users:**
- `fidel@aiphorism.net` (Fidel)
- `jack.watlington@gmail.com` (Jack)

**Supabase Auth settings required:**
- New user signups: DISABLED
- Redirect URL whitelisted: `https://quickshortsales.net/dashboard/`
- Both users invited via Authentication → Users → Invite

**Data access:** After auth, dashboard calls `sb.schema('jr_leads').from('properties')` using the authenticated user's session token. RLS on the table enforces access — anon cannot read directly.

**Features:** Lead table, distress score bars, hot/warm/cold badges, PRP validation status, equity figures, filter by status/stage/list/PRP, sortable columns, detail drawer with full property + campaign info, sign-out button.

---

## 7. Notification System

**Endpoint:** `https://aiphorism-client-portal.vercel.app/api/notify`  
**Source:** In the `rookstack/aiphorism-client-portal` GitHub repo — NOT cloned locally on this machine. Source must be pulled from GitHub to inspect or modify.

**Authentication:** `X-Notify-Key` header — value is a static secret validated against an env var on the Vercel project. The key is currently hardcoded in `index.html` and `short-sale-guide.html` (moving it server-side is a pending task).

**Current key:** In the page source of both public pages — grep for `X-Notify-Key`.

**Normal recipient:** `jack@fidelityrealtyadvisors.com` (Jack's working email)

**Payload shape (qr_scan type):**
```json
{
  "type": "qr_scan",
  "data": {
    "name": "OWNER FULL NAME",
    "address": "123 Main St",
    "city": "Miami",
    "state": "FL",
    "property_id": "<uuid>",
    "scan_count": "3",
    "is_first_scan": "false"
  }
}
```

**Payload shape (guide_form type):**
```json
{
  "type": "guide_form",
  "data": {
    "name": "Jane Smith",
    "email": "jane@email.com",
    "phone": "(305) 555-1234",
    "address": "123 Main St",
    "city": "Miami",
    "state": "FL",
    "zip": "33101",
    "source": "qr",
    "scan_count": "2"
  }
}
```

**Pending work on notify:**
- ZZTEST override: if `data.name` starts with `ZZTEST` (case-insensitive), send only to `fidel@aiphorism.net` and prefix subject with `[TEST]`. Source needs to be located in GitHub and edited.
- Move `X-Notify-Key` out of the public pages and into a server-side proxy (separate task).

---

## 8. Lead Import Process

Leads enter the system via Property Radar CSV exports, imported through the **Aiphorism client portal admin** (`clients.aiphorism.net/admin`). The portal admin authenticates via `ADMIN_SECRET` env var cookie.

**Rough flow:**
1. Pull a filtered export from Property Radar (distress score, equity, geography, etc.)
2. Import the CSV through the admin UI — this creates a record in `jr_leads.lists` and populates `jr_leads.properties`
3. Verify data quality using the `flags` column (`no_street_number`, `mail_differs`, `negative_equity`, `high_distress`, `business_owned`)
4. PRP validate (owner identity check via RPR) — update `prp_validated`, `prp_owner_match`
5. Postcards printed and mailed via Lob.com (manual for now — no API integration yet)

**⚠️ Note:** The exact import UI/API route in the client portal was not confirmed in local code — the route may only exist on the deployed Vercel instance or in the GitHub repo. Verify by inspecting `rookstack/aiphorism-client-portal` on GitHub.

---

## 9. Security State (as of handoff)

| Layer | Status |
|-------|--------|
| Anon direct SELECT on `properties` | Likely revoked — verify in Supabase RLS policies |
| Anon direct UPDATE on `properties` | Likely revoked |
| Anon direct INSERT on `form_submissions` | Likely revoked |
| Anon direct POST on `guide_leads` | Likely revoked |
| 5 SECURITY DEFINER RPCs | Live and tested end-to-end |
| Dashboard requires auth | ✅ Deployed |
| Table permissions for `authenticated` role | SELECT on properties/lists — read-only |

**To verify lockdown is complete:** Go to Supabase → Authentication → Policies. Confirm `properties` has no permissive anon UPDATE/INSERT policies remaining. The old `"anon can mark warm or hot"` policy from schema-update-003 should be dropped.

---

## 10. SQL Migration History

All files in `jr-leads-page/sql/`:

| File | What it does |
|------|-------------|
| `schema-update-001.sql` | Creates schema, `lists`, `properties`, `form_submissions`, triggers, indexes, role grants |
| `schema-update-002-flags.sql` | Adds `flags TEXT[]` column for data quality tagging |
| `schema-update-003-lead-status.sql` | Adds `lead_status`, `warm_at`, `hot_at` columns; old anon UPDATE policy (now superseded by RPCs) |
| `schema-update-004-form-submissions-rls.sql` | Old anon INSERT grant on `form_submissions` (now superseded by RPCs) |

RPC function DDL is **not** in the repo — it was written directly in the Supabase SQL editor. If replicating, those 5 functions need to be written fresh. Their signatures are fully documented in Section 4 above.

---

## 11. Replicating This for a New Client

To stand up the same system for a second client:

1. **Fork `jr-leads-page`** — update branding, copy, colors, phone numbers, Calendly link, YouTube embed, email addresses
2. **New Supabase project** — run all 4 SQL migrations in order, add the schema to PostgREST extra schemas
3. **Write the 5 RPCs** in the new project's SQL editor (same logic, new project)
4. **New domain** → GitHub Pages CNAME
5. **Invite dashboard users** and set the redirect URL in Supabase Auth
6. **Configure notify** — either reuse the existing endpoint with a new client key, or deploy a separate instance
7. **Property Radar** — set up the client's filter criteria; export CSVs for import
8. **Postcard templates** — update `postcard-stage1/2/3.html` with new branding and QR URL base

---

## 12. Open / Pending Items

- [ ] **ZZTEST notify override** — source not local; needs GitHub access to implement
- [ ] **Move X-Notify-Key server-side** — currently exposed in public page source
- [ ] **Verify full table lockdown** — confirm anon policies are dropped in Supabase
- [ ] **Confirm dashboard Supabase Auth settings** — disable signups, whitelist redirect URL, invite both users
- [ ] **Facebook Custom Audience sync** (`fb_synced_at` field exists, integration not built)
- [ ] **Lob.com API integration** — mailer automation (currently manual)
- [ ] **RPC DDL in repo** — the 5 RPC function definitions should be saved to `sql/` for reproducibility

---

## 13. Key Contacts / Credentials Location

- **Jack Watlington:** jack.watlington@gmail.com, jack@fidelityrealtyadvisors.com
- **Fidel (Aiphorism):** fidel@aiphorism.net
- **Supabase keys:** In `.env.local` of `aiphorism-client-portal` (service role) and inline in page source (anon key)
- **Vercel env vars:** Set on the `aiphorism-client-portal` Vercel project — includes `NOTIFY_KEY` (or equivalent) and any email provider keys
- **GitHub org:** `rookstack`
