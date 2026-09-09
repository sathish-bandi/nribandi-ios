# NRIBANDI iOS

Native **SwiftUI** client for the NRIBANDI rental-property backend.

This repository is **iOS only**. The Spring Boot API lives in a separate repo:
[`sathish-bandi/rental-property-app`](https://github.com/sathish-bandi/rental-property-app).

## Environments

| App picker | Backend Spring profile | API base URL |
|---|---|---|
| **Local** | `local` | `http://127.0.0.1:8082` (Docker API on your Mac) |
| **TEST** | `qa` | `NribandiTestAPIBaseURL` in `Nribandi/Resources/Info.plist` |
| **PROD** | `prod` | `NribandiProdAPIBaseURL` in `Nribandi/Resources/Info.plist` |

**Debug (Xcode Run on your Mac):** Local / TEST / PROD picker is shown on Login and Profile.

**App Store / TestFlight (Release):** no environment picker — the app always uses **PROD**.

Changing environment in Debug signs you out.


## Quick start scripts (Mac)

From this repo:

```bash
chmod +x START-ON-MAC.command CHECK-BACKEND.command scripts/*.sh
./scripts/run-local.sh
```

Or in Finder:

- **`START-ON-MAC.command`** — checks Local backend (`:8082`), then opens Xcode
- **`CHECK-BACKEND.command`** — only checks whether the API is up

Then in Xcode press **Run (⌘R)**. Keep environment **Local**.

Login: `admin@nribandi.local` / `Nribandi@123`

To verify tenant detail + permanent address: People → Tenants → **Priya Menon**
(or sign in as `priya.menon@nribandi.local` / `Nribandi@123`). Requires local seed.

The backend must be started separately from
[`rental-property-app`](https://github.com/sathish-bandi/rental-property-app)
(`./scripts/local-up.sh` or `START-ON-MAC.command` there).


## Run on your MacBook

### 1. Start the backend (separate repo)

```bash
git clone https://github.com/sathish-bandi/rental-property-app.git
cd rental-property-app
cp .env.local.example .env
./scripts/local-up.sh
```

Health: http://localhost:8082/actuator/health

### 2. Open this iOS app

Requires **Xcode 15+**.

```bash
git clone https://github.com/sathish-bandi/nribandi-ios.git
cd nribandi-ios
open Nribandi.xcodeproj
```

1. Select an **iPhone Simulator**
2. Press **Run** (⌘R)
3. Keep environment on **Local**
4. Sign in:

```
admin@nribandi.local
Nribandi@123
```

Local uses `127.0.0.1:8082` so the Simulator reaches Docker on your Mac.

## TEST / PROD

Edit `Nribandi/Resources/Info.plist` with your AWS API URLs.
- **PROD (temporary):** `http://13.235.9.106:8082` — for Simulator/Debug against EC2.
- Before **App Store**, switch to HTTPS (`https://api.yourdomain.com`) and remove the IP ATS exception.

In **Debug**, pick **TEST** or **PROD** in the app. **Release / App Store** always uses PROD.

## What’s included

- JWT login / logout (refresh on 401)
- Dashboard (ADMIN / EMPLOYEE)
- Properties + units with **tenant / vacant** status on unit lists
- **Unit detail:** current tenant (tap for People KYC), tenancy duration, rental agreement PDF, recent inspections with media, to-let enquiries on vacant units (staff CRUD, max 10)
- Service requests with repair estimate, payer confirmation, payment-pending display statuses, and linked invoice
- Company UPI / GPay / PhonePe payment IDs (admin manage; shown on invoices and pending SRs — no payment gateway)
- Global enquiries
- Profile (+ environment switcher in Debug only)

## Demo (Local seed)

After seeding the backend (`./scripts/local-seed.sh` in the API repo):

| Scenario | Where |
|---|---|
| Tenanted unit + agreement PDF + inspections | Properties → unit with Priya / Rahul |
| Pre-move-in inspection hidden from tenant | Login as `priya.menon@nribandi.local` → her unit inspections |
| Vacant to-let enquiries | Vacant unit `101` on seeded apartment |
| Agreement renewing soon | Priya’s tenancy (ends ~12 days out) |

Password for all seed accounts: `Nribandi@123`
