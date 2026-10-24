# CertiTrustWeb

CertiTrust Web is the React/Vite interface for the CertiTrust credential system.

## Development

```powershell
npm install
npm run dev
```

## Checks

```powershell
npm run lint
npm run build
```

The Laravel API is maintained in the sibling `CertiTrust` project and is deployed at `https://certitrust-yhzl.onrender.com`. The web app uses this live API by default, so you do not need to run Laravel locally.

For local development, copy `.env.example` to `.env.local`. The default uses the live Render API; set `VITE_API_BASE_URL` to a local Laravel API only when you intentionally want to develop against one. Production deployments can leave `VITE_API_BASE_URL` unset or set it to the Render API URL. Set Laravel's `WEB_APP_URL` to the deployed frontend origin so the browser can make cross-origin API requests.

Google sign-in opens Google's account-picker popup and requires each development origin you use (for example, `http://localhost:5173` or `http://127.0.0.1:5181`) to be listed under **Authorized JavaScript origins** for the OAuth web client configured by `VITE_GOOGLE_CLIENT_ID` in Google Cloud Console. Add the deployed frontend origin there as well when deploying the web app. If Google reports that the origin is not allowed, add the exact origin in Google Cloud Console; email/password login cannot authenticate a Google account. The web API uses bearer tokens and does not require cross-origin cookies.

## Shared Laravel API

- `src/services/apiClient.ts` provides the base URL and adds the current Sanctum bearer token to requests.
- `src/services/authService.ts` handles login, session lookup, logout/revocation, student-ID checks, and profile updates.
- `src/services/certitrustApi.ts` handles certificate listing, file upload, batch issuance/validation, verification, and deletion requests.
- `src/services/adminApi.ts` and `src/services/chatApi.ts` mirror the admin, access-control, deletion-review, Super Admin Junk cleanup, and chat endpoints used by Flutter.
- `src/hooks/` contains list/polling hooks for certificates, users, certificate batches, and chat.

React keeps the bearer token in `sessionStorage` by default; selecting Remember me stores it in `localStorage`. Both are readable by same-origin JavaScript. For stronger browser token protection, move authentication to an HttpOnly, Secure, SameSite cookie flow.

Public and admin certificate verification support camera-based QR scanning and QR images. Camera access requires a secure context (HTTPS or localhost) and the user must allow camera permission in the browser. The Super Admin Junk page is a shared recycle bin for removed subadmins, approved student-account removals, and revoked credentials. Student removal requests require Super Admin approval before they enter Junk; Junk items are permanently deleted only after a separate confirmation. Removed QR codes report as removed, while blockchain transactions remain immutable.

Open certificate, student, admin, and chat lists poll Laravel every five seconds, so changes from Flutter appear on the next poll. This project does not currently configure Laravel broadcasting/Reverb; use Reverb or another authenticated push channel if sub-five-second live updates are a requirement. Supabase PostgreSQL remains the shared database behind Laravel; React and Flutter should not write directly to privileged tables.
