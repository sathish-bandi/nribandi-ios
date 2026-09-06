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

Switch environment on the login screen or in **Profile**. Changing environment signs you out.

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

Edit `Nribandi/Resources/Info.plist` with your AWS API HTTPS URLs, then pick **TEST** or **PROD** in the app.

## What’s included

- JWT login / logout (refresh on 401)
- Dashboard (ADMIN / EMPLOYEE)
- Properties + units
- Service requests
- Enquiries
- Profile + environment switcher
