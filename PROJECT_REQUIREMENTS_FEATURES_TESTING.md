# Project Requirements, Features, and Testing

**Project Title:** CertiTrust: Blockchain-Based Digital Identity and Academic Records Verification System

**Tester:** Development Team / Group 7

**Date:** October 27, 2026
**Document status:** Requirements and test-case template; test execution results have not been recorded.

> **Scope and implementation note:** The system provides institution-scoped workflows for academic credential management. For this capstone, the study's pilot implementation and testing are limited to Urdaneta City University (UCU) and Pangasinan State University (PSU) Urdaneta. The project is not claiming implementation or testing at every university. This document reflects the checked-in CertiTrust mobile, web, and Laravel projects. The repository currently configures Ethereum Sepolia (chain ID `11155111`), while the requested project description specifies Polygon Amoy. These are different networks: confirm the required target and deploy/configure the matching contract before treating Amoy anchoring as accepted. The repository documentation also describes chat updates as polling approximately every five seconds; it does not currently configure Laravel broadcasting/Reverb. Accordingly, chat tests below expect periodic refresh, not instantaneous push delivery.

## I. Project Requirements

### A. Hardware and connectivity

| ID | Requirement |
|---|---|
| HW-01 | Development workstation capable of running Flutter, PHP/Laravel, Node.js/Vite, a supported browser, and a local test database concurrently. Final CPU, RAM, and disk minimums should be confirmed against the team's available equipment; no project-specific minimum is defined in the repository. |
| HW-02 | Android device or emulator with camera access for QR scanning. A physical-device test is required because emulator camera behavior may differ. |
| HW-03 | iOS device/simulator if iOS is an intended deliverable; camera permission and QR scanning must be checked on supported hardware. |
| HW-04 | Desktop/laptop with a current supported browser, webcam/camera, and HTTPS or localhost origin to test browser camera scanning. |
| HW-05 | Reliable internet connection for Laravel API, Supabase database/storage, Google sign-in, and blockchain RPC access. |
| HW-06 | Dedicated test wallet funded only with test-network tokens if blockchain writes are enabled. Do not use a personal/mainnet wallet. |

### B. Software and services

| ID | Requirement |
|---|---|
| SW-01 | Flutter SDK and Dart SDK compatible with the mobile project (`Dart >=3.5.0 <4.0.0`); Flutter package dependencies restored with `flutter pub get`. |
| SW-02 | PHP 8.2 or compatible and Composer dependencies for Laravel 11; backend tests run with the project's PHPUnit setup. |
| SW-03 | Node.js/npm compatible with the React 19/Vite 8 web project; dependencies restored with `npm install`. |
| SW-04 | Current Android SDK/Gradle toolchain for Android builds. Configure Android runtime permissions for camera and file access where applicable. |
| SW-05 | Xcode and supported macOS environment if building or testing the iOS app. |
| SW-06 | Laravel API deployment/runtime configured with HTTPS, allowed frontend origins (CORS), correct `WEB_APP_URL`, and required environment variables. |
| SW-07 | Google OAuth web client configured with the exact development and deployment origins used by the web client. Backend Google token validation must use the matching client ID. |
| SW-08 | Supabase project with PostgreSQL for the shared application data and Storage for diploma documents and chat attachments. Configure the Laravel backend with `SUPABASE_URL` and a secret/service-role key. Never expose the service-role key in the mobile or web client. |
| SW-09 | Laravel Sanctum bearer-token authentication for authenticated API operations. Clients must attach the active token and handle expiry, logout, and authorization failures. |
| SW-10 | Ethereum-compatible JSON-RPC endpoint(s), a deployed compatible CertiTrust contract, contract address, chain ID/network, and backend signer credentials held only in protected backend configuration when blockchain writes are enabled. |
| SW-11 | Configure the intended test network consistently across the contract, backend RPC/network settings, explorer references, and test documentation. **Open decision:** current checked-in values describe Ethereum Sepolia; Polygon Amoy is not the configured target. |
| SW-12 | QR code generation and scanning dependencies available in both clients; browser scanning requires a secure context and user-granted camera permission. |
| SW-13 | Local/test database configuration for Laravel migrations and automated tests. The sample backend environment defaults to SQLite; deployed shared records are documented as Supabase PostgreSQL. |
| SW-14 | Browser support target (browser/version matrix) and supported mobile OS/device versions must be selected by the project team and recorded before final acceptance; these are not fixed by the repository. |

### C. Functional requirements

| ID | Requirement |
|---|---|
| FR-01 | The system shall provide separate student, university administrator/subadmin, and Super Admin experiences for the participating institutions of UCU and PSU Urdaneta, with server-side role and university-scope authorization. |
| FR-02 | Users shall be able to authenticate using supported credentials; Google sign-in shall be supported where configured. Super Admin Google provisioning/login has dedicated behavior; confirm account-provisioning policy for other roles. |
| FR-03 | The system shall support session restoration, authenticated logout/token revocation, and route protection. Restricted/frozen users shall receive the intended restricted experience. |
| FR-04 | Users shall be able to view and update supported profile information. University identity and role data shall remain controlled by authorized backend workflows. |
| FR-05 | Students shall be able to access their own issued credential records and available diploma files; administrators shall manage records within their authorized university scope for UCU or PSU Urdaneta. |
| FR-06 | Authorized university administrators shall issue credentials individually or in batches, validate batch data, detect duplicate diploma filenames as supported, and upload associated diploma files. |
| FR-07 | Credential records shall have a normalized SHA-256 identity/hash used for QR and verification workflows. Personal academic information and diploma contents shall not be written to the public chain; only contract-defined hashes/metadata required for verification should be anchored. |
| FR-08 | The system shall generate a QR code or verification link for a credential and allow supported clients to display, download, or scan it. |
| FR-09 | Public verification shall look up a credential by its code/hash and return an understandable result, including revoked/removed status and blockchain verification status where available. |
| FR-10 | When enabled and correctly configured, Laravel shall submit credential issuance to the selected testnet contract and retain the transaction hash, network, and blockchain status. The system shall distinguish RPC submission from mined/confirmed transactions. |
| FR-11 | Authorized users shall be able to request credential deletion; a Super Admin shall review requests. Approved removals shall be represented in the system as revoked/removed without implying that an immutable blockchain transaction was erased. |
| FR-12 | Authorized administrators shall manage student/subadmin access, including supported account freezes, updates, and removals. Student removals requiring approval shall follow the Super Admin review workflow. |
| FR-13 | The Super Admin shall be able to manage participating university/subadmin records and review institution-specific system records, overview data, recent verifications, and administrative action history for the UCU and PSU Urdaneta pilot scope. |
| FR-14 | The Super Admin shall be able to review the Junk/recycle bin and permanently delete supported items only after confirmation. |
| FR-15 | Authenticated users shall be able to view chat contacts/conversations, send and receive messages, use supported replies/attachments, and see available presence/delivery information. |
| FR-16 | Chat clients shall refresh messages and lists using the implemented polling behavior (approximately every five seconds for open lists); push-based, sub-five-second delivery is not currently established. |
| FR-17 | Users shall be able to delete supported messages or clear conversations subject to server authorization. |
| FR-18 | The API shall provide a health endpoint and return clear success/error responses for client integration and operational checks. |

### D. Non-functional and operational requirements

| ID | Requirement |
|---|---|
| NFR-01 | All production client-to-API and API-to-service traffic shall use HTTPS/TLS. |
| NFR-02 | Authorization shall be enforced by Laravel, not solely by hidden client screens. Student records and university data shall be scoped to the authenticated user/role. |
| NFR-03 | Secrets (Google credentials, Supabase service-role key, blockchain signer private key, application keys) shall be kept in protected deployment secrets and excluded from source control and client bundles. |
| NFR-04 | The system shall validate input and uploaded files, handle unavailable APIs/services explicitly, and avoid presenting failed blockchain writes as successful on-chain issuance. |
| NFR-05 | The interface shall provide loading, empty, success, and error states for network-backed workflows; destructive account, record, and message actions shall be confirmation-gated where implemented. |
| NFR-06 | Account and credential changes requiring elevated permissions shall be auditable through the supported admin action history. |
| NFR-07 | Blockchain verification shall use the normalized hash and configured contract/network. RPC/network errors and transaction submission status shall be distinguishable from a valid on-chain credential. |
| NFR-08 | Publicly accessible verification and file links shall expose only information approved for public verification. Diploma storage is documented as public URL access; the institution must approve that privacy model and the data displayed. |
| NFR-09 | Automated tests shall be run in the relevant Flutter, Laravel, and web projects; cross-platform acceptance tests shall cover workflows that unit tests do not exercise. |
| NFR-10 | Backups, retention, recovery objectives, accessibility target, performance thresholds, expected concurrent users, and uptime targets must be agreed by the institution; the repository does not define numeric service-level targets. |
| NFR-11 | Chat polling interval, availability expectations, and message/file retention policy shall be documented. If near-instant updates are an acceptance requirement, an authenticated push/broadcasting solution must be added and separately tested. |
| NFR-12 | Network choice (Polygon Amoy versus Ethereum Sepolia), contract deployment, test wallet management, and testnet explorer verification shall be signed off before blockchain acceptance testing. |

## II. Project Features

Descriptions below are based on the implemented application surfaces and backend routes. “Not currently implemented/configured” notes identify limits that must not be presented as completed behavior.

| ID | Platform / role | Feature | Description |
|---|---|---|---|
| F-01 | Mobile, web; all roles | Role-aware sign-in | Authenticates users through the Laravel API and routes users to role-appropriate areas. Google sign-in is available where configured; Super Admin has a dedicated Google login/provisioning flow. |
| F-02 | Mobile, web; authenticated users | Session restoration and logout | Restores an existing API session when reopening the app and logs out by revoking the active Sanctum token. Web token persistence supports session storage and an optional “Remember me” local-storage mode. |
| F-03 | Mobile, web; all roles | Student ID verification | Provides the supported student-ID check during account/login workflows before proceeding. |
| F-04 | Mobile, web; all roles | Profile management | Displays and updates supported user profile details. Mobile includes profile-photo selection/update behavior; available fields depend on role and backend validation. |
| F-05 | Mobile, web; students | Student dashboard | Provides the student landing view with access to credential records and supported verification actions. |
| F-06 | Mobile, web; administrators | University admin dashboard | Displays the university-scoped administrative dashboard and links to records, issuance, access, verification, and other authorized functions. |
| F-07 | Mobile, web; Super Admin | Super Admin dashboard/overview | Provides global administrative overview and navigation to university, account, credential, log, and cleanup workflows. |
| F-08 | Mobile, web; students | Student credential records | Lists the authenticated student's academic credential records and available credential details. |
| F-09 | Mobile, web; students/admins | Diploma preview and download | Opens or downloads an attached diploma where a stored document and accessible URL exist. |
| F-10 | Mobile, web; administrators | Credential record management | Lists/searches available credential records within the role's authorized scope and opens record detail/actions. |
| F-11 | Mobile, web; university admins | Individual credential issuance | Creates a credential from entered academic/student data using the protected Laravel API. |
| F-12 | Mobile, web; university admins | Batch credential issuance | Validates and issues multiple credentials using the batch endpoint and reports record-level validation/issuance outcomes. |
| F-13 | Mobile, web; university admins | Credential/diploma file upload | Associates a diploma document with a credential using the backend and Supabase Storage. |
| F-14 | Mobile, web; university admins | Batch validation and filename checks | Validates batch issuance data and checks diploma filename conflicts before submission where supported. |
| F-15 | Mobile, web; students/admins | Credential QR generation | Displays a QR/verification representation for a credential; supported clients can save or download QR output. |
| F-16 | Mobile; public/authenticated as routed | Mobile QR camera scanning | Uses the device camera to read a credential QR code and proceeds to verification. Camera permission is required. |
| F-17 | Web; public/admin as routed | Web QR scanning and QR image input | Scans using a browser camera in HTTPS/localhost with permission and supports QR-image based verification. |
| F-18 | Mobile, web; public | Public credential lookup | Verifies a record by its public code/hash without requiring an authenticated credential-list session. |
| F-19 | Mobile, web; public/admin | Verification result and multiple-degree checks | Shows certificate verification outcomes, including supported handling of multiple credentials/degrees and follow-up verification flows. |
| F-20 | Backend, mobile, web | Blockchain issuance anchoring | On successful configured issuance, the backend submits the credential's normalized hash/contract-defined values and stores network, transaction hash, and status. Chain writes are optional/configuration-dependent. |
| F-21 | Backend, mobile, web | On-chain verification | Calls the configured contract to check the credential hash and surfaces the contract validity result alongside the application record. Current checked-in network is Ethereum Sepolia, not Polygon Amoy. |
| F-22 | Mobile, web; students/admins | Credential deletion request | Submits a request for review rather than directly erasing a credential. |
| F-23 | Mobile, web; Super Admin | Credential deletion request review | Lists pending requests and allows supported approval/rejection actions; approved records are revoked/removed from active use and handled through cleanup workflow. |
| F-24 | Mobile, web; university admin | Student access management | Lists/manages student access for the administrator's university, including supported per-student and bulk access changes. |
| F-25 | Mobile, web; university admin | Student account removal request | Submits a student-removal request for higher-level review where required; this is distinct from immediate permanent deletion. |
| F-26 | Mobile, web; Super Admin | Student removal approval | Reviews student deletion requests and applies supported approval/rejection workflow before removal proceeds to Junk. |
| F-27 | Mobile, web; Super Admin | University/subadmin management | Lists universities and subadmins; supports supported subadmin creation/binding, updates, unbinding Google association, and removal. |
| F-28 | Mobile, web; Super Admin | Access freeze and restricted chat | Freezes supported accounts or university access. A frozen account is routed to a restricted chat experience/contact rather than normal application access. |
| F-29 | Mobile, web; Super Admin | Junk/recycle-bin management | Lists supported removed subadmins, approved student removals, and revoked credentials; supports confirmed permanent deletion of eligible items. |
| F-30 | Mobile, web; Super Admin | Administrative action history | Displays available admin action logs for accountability. |
| F-31 | Mobile, web; administrators | Recent verification activity | Displays supported recent credential-verification activity in administrative views. |
| F-32 | Mobile, web; users | Chat contact list and inbox | Lists available contacts/conversations for the authenticated role and opens the corresponding chat. |
| F-33 | Mobile, web; users | One-to-one chat messaging | Sends and retrieves messages through authenticated Laravel chat endpoints. Open chat/list views refresh by polling (approximately five seconds), not a configured push channel. |
| F-34 | Mobile, web; users | Chat replies and attachments | Supports reply/conversation fields and message attachments stored through Supabase Storage where the client workflow accepts a file. |
| F-35 | Mobile, web; users | Chat presence and delivery information | Updates user last-seen presence and exposes available presence/delivery timestamps; do not treat these as read receipts unless separately confirmed. |
| F-36 | Mobile, web; users | Message deletion and conversation clearing | Deletes supported messages or clears a conversation through authenticated endpoints, subject to ownership/role rules and soft-deletion behavior. |
| F-37 | Mobile, web; administrators | Admin notifications/inbox surfaces | Provides the implemented admin inbox/notification views for supported requests and system activity; this is not a claim of push notifications. |
| F-38 | Backend; operations | API health check | Exposes root/health responses for deployment and connectivity checks. |
| F-39 | Mobile, web; authenticated users | Role-restricted navigation | Prevents or redirects users away from routes/actions not available to their role, with the backend remaining the authorization authority. |

## III. Feature Testing

**Execution rule:** The actual-results values are intentionally marked **Not run**. Enter observed evidence only after executing the test on the named client/API with the relevant test account, data, environment, and network. Mark Pass/Fail only after comparing the observation to expected behavior.

| ID | Feature / test case | Test procedure (summary) | Expected result | Actual result | Status |
|---|---|---|---|---|---|
| F-01 | Role-aware sign-in | Sign in with valid student, university admin, and Super Admin test accounts; exercise configured Google sign-in. | Each valid account authenticates and reaches only its intended role experience; invalid credentials/provider configuration show an error without granting access. | Not run — record observed result/evidence. | Pending |
| F-02 | Session restoration and logout | Sign in, close/reopen client, then log out and attempt to revisit a protected route. Test web Remember me behavior. | Valid sessions restore as designed; logout revokes access and protected views require authentication; configured persistence behaves as described. | Not run — record observed result/evidence. | Pending |
| F-03 | Student ID verification | Submit a valid, invalid, and malformed student ID through the supported verification step. | Valid ID proceeds; invalid/unrecognized or malformed input is rejected with clear feedback and does not create an authenticated session. | Not run — record observed result/evidence. | Pending |
| F-04 | Profile management | View and update supported fields; on mobile, select/update a profile photo if enabled. Reload profile. | Valid changes persist and display consistently; invalid fields are rejected; user cannot change protected role/university attributes without authorization. | Not run — record observed result/evidence. | Pending |
| F-05 | Student dashboard | Sign in as a student with records and as a student without records. | Dashboard loads only the signed-in student's data, offers available actions, and shows a useful empty state when no records exist. | Not run — record observed result/evidence. | Pending |
| F-06 | University admin dashboard | Sign in as a university administrator and load dashboard data. | Dashboard loads authorized university-scoped information and relevant navigation; other universities' records are not exposed. | Not run — record observed result/evidence. | Pending |
| F-07 | Super Admin dashboard/overview | Sign in as Super Admin and open the overview. | Global overview data and authorized administration links load; non-Super Admin cannot access the same protected API data. | Not run — record observed result/evidence. | Pending |
| F-08 | Student credential records | View a student account with multiple records and another student's account. | The student sees their own records only; records show correct credential details and unauthorized record access is denied. | Not run — record observed result/evidence. | Pending |
| F-09 | Diploma preview/download | Open and download an existing diploma; try missing/unavailable file and unauthorized access. | Existing authorized document opens/downloads; absent, inaccessible, or unauthorized files show a clear failure without exposing another student's document. | Not run — record observed result/evidence. | Pending |
| F-10 | Credential record management | As admin, list and open records; attempt access outside the admin's university scope. | Authorized records and supported search/list actions work; cross-university access is denied or excluded. | Not run — record observed result/evidence. | Pending |
| F-11 | Individual credential issuance | Submit a valid credential; repeat with missing/invalid required fields and a duplicate case. | Valid credential is stored once with expected student/academic data and response; invalid or duplicate data is rejected with actionable feedback. | Not run — record observed result/evidence. | Pending |
| F-12 | Batch credential issuance | Submit a valid multi-record batch, a mixed-validity batch, and an empty batch. | Valid items are processed according to documented batch semantics; invalid rows are reported; empty input is rejected; no false all-success result is shown. | Not run — record observed result/evidence. | Pending |
| F-13 | Credential/diploma file upload | Upload an allowed diploma file with a valid credential; test unsupported/oversized file and storage outage. | Accepted file is stored and linked to the correct credential; invalid files and service failures return clear errors without orphaned/success-shaped records. | Not run — record observed result/evidence. | Pending |
| F-14 | Batch validation and filename checks | Validate a batch with unique filenames and with repeated/conflicting filenames. | Validation returns accurate row-level issues and filename conflicts before issuance; no unintended duplicate document overwrite occurs. | Not run — record observed result/evidence. | Pending |
| F-15 | Credential QR generation | Generate QR for a valid credential; scan/inspect QR payload and test save/download. | QR resolves to the intended public verification flow and represents the right credential; supported save/download succeeds and errors are visible. | Not run — record observed result/evidence. | Pending |
| F-16 | Mobile QR camera scanning | Grant camera access and scan valid, invalid, and unreadable codes; deny permission once. | Valid QR opens correct verification; invalid/unreadable content is handled safely; denied permission is communicated and recoverable. | Not run — record observed result/evidence. | Pending |
| F-17 | Web QR scanning and QR image input | On HTTPS/localhost, grant camera permission and scan a valid QR; then use an image and test denied permission/non-secure origin. | Supported valid QR resolves to verification; unsupported context, denied permission, and unreadable image produce clear user feedback. | Not run — record observed result/evidence. | Pending |
| F-18 | Public credential lookup | Verify a valid credential code/hash and unknown/malformed code while logged out. | Valid public record returns the approved public details and status; invalid/unknown values do not reveal private data and return a clear not-found/invalid result. | Not run — record observed result/evidence. | Pending |
| F-19 | Verification result and multiple degrees | Verify valid, revoked, altered/unknown, and multi-degree student records. | UI distinguishes valid, invalid, revoked/removed, and available multiple-degree results; each result corresponds to the correct credential. | Not run — record observed result/evidence. | Pending |
| F-20 | Blockchain issuance anchoring | With the approved testnet, enabled setting, funded test signer, and compatible contract, issue a credential and inspect backend status/transaction hash and explorer. Also test disabled/unavailable RPC. | Enabled issuance records the correct transaction/network/status; pending submission is not labeled mined; disabled or failed RPC is reported accurately and does not claim chain success. | Not run — record network, tx hash, and evidence. | Pending |
| F-21 | On-chain verification | Verify a known anchored hash, unknown hash, revoked credential, and unavailable RPC against the configured deployed contract. | Result matches the contract's validity response and configured network; RPC failure is distinct from an invalid credential. Confirm Amoy only if Amoy is selected and configured. | Not run — record network and evidence. | Pending |
| F-22 | Credential deletion request | Submit a deletion request as an eligible user for an existing credential; try unauthorized and duplicate requests. | Eligible request is recorded for review; unauthorized or invalid/duplicate request is rejected or handled according to the defined policy with visible status. | Not run — record observed result/evidence. | Pending |
| F-23 | Credential deletion request review | As Super Admin, list requests, approve one, reject another, and try a non-Super Admin account. | Authorized review updates request/credential state as designed; rejection preserves active credential; unauthorized reviewer is denied; chain history remains immutable. | Not run — record observed result/evidence. | Pending |
| F-24 | Student access management | As university admin, view students, change one student's access, apply supported bulk change, and attempt cross-university action. | Changes apply only within authorized scope, persist, and are reflected in access behavior; invalid/unauthorized action is denied. | Not run — record observed result/evidence. | Pending |
| F-25 | Student account removal request | Request removal of a student account as an authorized admin; test unauthorized role. | Request is queued for Super Admin review instead of being silently/permanently deleted; unauthorized request is denied. | Not run — record observed result/evidence. | Pending |
| F-26 | Student removal approval | As Super Admin, approve and reject separate student removal requests. | Approval follows the documented removal-to-Junk workflow; rejection leaves account active; request status and action are traceable. | Not run — record observed result/evidence. | Pending |
| F-27 | University/subadmin management | Create/bind, update, unbind Google association, and remove a subadmin; inspect university-scoped student listing. | Authorized changes persist and correct scope/role is retained; invalid or non-Super Admin actions are denied; related data follows documented retention workflow. | Not run — record observed result/evidence. | Pending |
| F-28 | Access freeze and restricted chat | Freeze a test account; sign in/reload as that account, use restricted chat, and unfreeze. | Frozen user cannot continue normal protected workflows and is routed to intended restricted contact/chat; authorized unfreeze restores normal access. | Not run — record observed result/evidence. | Pending |
| F-29 | Junk/recycle-bin management | As Super Admin, inspect supported Junk item types, restore/retain where available, and permanently delete an eligible item after confirmation. | Only eligible items appear; permanent deletion requires confirmation and removes the selected item; immutable chain data is not represented as erased. | Not run — record observed result/evidence. | Pending |
| F-30 | Administrative action history | Perform representative admin operations and open action history as Super Admin and a lower role. | Supported actions show correct actor/action/time/details; unauthorized users cannot view global history. | Not run — record observed result/evidence. | Pending |
| F-31 | Recent verification activity | Verify test credentials and view the admin recent-verification list. | Supported verification activity appears with correct record/time and authorized scope; no unrelated private information is exposed. | Not run — record observed result/evidence. | Pending |
| F-32 | Chat contact list and inbox | Sign in as student and admin; load contacts/inbox and open an allowed conversation. | Each role sees only authorized contacts/conversations; empty, loading, and API error states are handled. | Not run — record observed result/evidence. | Pending |
| F-33 | One-to-one chat messaging | Send/receive messages from two accounts; keep a conversation open and measure refresh behavior. | Messages persist and appear to the recipient on the implemented polling cycle (about five seconds); no push/sub-five-second expectation is asserted. | Not run — record observed result/evidence. | Pending |
| F-34 | Chat replies and attachments | Reply to a message and send an allowed attachment; test unavailable storage and unauthorized conversation. | Reply links and attachment are associated with the correct conversation; storage/authorization errors are visible and do not leave a false-success state. | Not run — record observed result/evidence. | Pending |
| F-35 | Chat presence and delivery information | Sign in/out or update presence from two accounts; send a message and inspect available timestamps. | Last-seen and delivery fields update according to implementation; UI does not claim a read receipt unless one is implemented. | Not run — record observed result/evidence. | Pending |
| F-36 | Message deletion and conversation clearing | Delete an eligible message and clear a test conversation; attempt unauthorized deletion. | Authorized operation updates the conversation using the configured deletion behavior; unauthorized operation is denied and other conversations remain intact. | Not run — record observed result/evidence. | Pending |
| F-37 | Admin notifications/inbox surfaces | Open admin inbox/notification views with and without supported requests/activity. | Implemented items load and link to correct workflow; empty/error states are clear; no unsupported push-delivery claim is made. | Not run — record observed result/evidence. | Pending |
| F-38 | API health check | Request the backend root and `/health` endpoints in a running test environment. | API returns its expected healthy status payload; unavailable service is detected as a connectivity failure. | Not run — record HTTP status/payload. | Pending |
| F-39 | Role-restricted navigation | Attempt role-inappropriate routes and direct protected API requests using each test role, including frozen account. | Client redirects/hides restricted views as appropriate and backend denies unauthorized API actions regardless of client navigation. | Not run — record observed result/evidence. | Pending |

## IV. Testing Summary

Complete this summary after all applicable test cases in Section III have been executed. Do not count unexecuted tests as passed.

| Summary item | Result |
|---|---|
| Total features/test cases listed | 39 |
| Total features/tested | [Enter count] |
| Features passed | [Enter count] |
| Features failed | [Enter count] |
| Features blocked/not run | [Enter count] |
| Issues or bugs found | [List issue IDs, concise description, severity, and affected feature IDs; write “None observed” only after execution.] |
| Test environment | [Device/OS, browser/version, app build, API environment, database, and blockchain network/chain ID] |
| Test data/accounts | [Identify test data/accounts without recording passwords, tokens, private keys, or other secrets.] |
| Tester's remarks | [Overall assessment, known limitations, unresolved decisions (including Amoy vs Sepolia), retest needs, and release recommendation.] |
| Tester signature / date | [Name/signature and completion date] |

### Suggested acceptance checklist

- [ ] All applicable test cases have actual results and evidence recorded.
- [ ] Failed cases have issue IDs, owners, and retest outcomes.
- [ ] Role-scope and public-verification privacy checks pass.
- [ ] Network target has been approved and contract, backend, and verification environment agree.
- [ ] Blockchain test results include the configured network and transaction evidence where an on-chain write was expected.
- [ ] Chat acceptance criteria explicitly match polling or an implemented push/broadcasting solution.
- [ ] Outstanding policy decisions (privacy of diploma URLs, data retention, service levels, and supported device/browser matrix) have institutional approval.
