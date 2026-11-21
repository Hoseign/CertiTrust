# CertiTrust UCU Research and UAT Scope

**Project title:** CertiTrust: A Blockchain-Based Digital Identity and Academic Records Verification System  
**Institution covered by this document:** Urdaneta City University (UCU)  
**Document purpose:** Describe the UCU-focused research and user acceptance testing (UAT) scope. This file is explanatory thesis documentation, not application configuration.

## 1. Research scope

This document describes evaluation of CertiTrust in the context of Urdaneta City University. It is intentionally limited to UCU as the institution of focus for this research description. It does not claim that every feature, institution policy, or deployment detail has been independently accepted by UCU.

The repository's broader pilot documentation identifies UCU and Pangasinan State University (PSU) Urdaneta as participating institutions. This UCU document narrows the discussion to the UCU research context; it does not change the app's university records, access rules, or runtime behavior.

## 2. Institution profile for the study

| Item | UCU research scope |
|---|---|
| Institution name | Urdaneta City University |
| Institution code | UCU |
| Address / location | San Vicente West, Urdaneta City, Pangasinan |
| Office in focus | Office of the University Registrar |
| Mobile platform | Flutter mobile application, with Android APK as the stated UAT target |
| Web administration platform | React/Vite web client and Laravel 11 API |
| Data services | Supabase PostgreSQL and Supabase Storage; database Row Level Security (RLS) policies are present for selected tables |
| Requested blockchain target for research | Polygon Amoy Testnet |
| Document types in this UCU research scope | Diploma; Transcript of Records (TOR) |

The platform and document scope above describe the intended UCU research evaluation. They should not be read as proof that all those items are enforced as exclusive runtime restrictions in the checked-in application.

## 3. System context and functions evaluated

CertiTrust is intended to support digital academic credential management and verification. The system includes student, university administrator, and Super Admin experiences. Relevant functions for UCU-focused evaluation include:

- Account sign-in, session handling, and role-aware access to application areas.
- Viewing a student's available academic credential records.
- University administrator workflows for creating individual or batch credential records.
- Attaching and retrieving diploma files through the configured storage service.
- Generating a QR representation and looking up a credential through the verification flow.
- Checking a credential's record status and, when blockchain services are enabled and correctly configured, checking its hash against the deployed contract.
- Submitting credential deletion requests for review, managing supported account access, and recording administrative actions.

These are system capabilities, not a statement that every function has completed UCU UAT. Record test dates, participants, observed results, and evidence separately in the study's test results.

## 4. Credential data and blockchain handling

The application stores credential details in the backend, including university code, academic/student fields, document URL where available, a credential hash, and blockchain status/transaction metadata. The design uses a normalized SHA-256 hash for credential verification. Blockchain operations are optional and depend on backend settings, a compatible deployed contract, RPC access, and protected signer configuration.

Do not represent personal academic data or diploma contents as public blockchain data. The implementation is intended to anchor contract-defined hashes/values and keep the credential record and document storage in application services. A submitted transaction is not necessarily a mined or confirmed transaction, and blockchain history is not erased by an application-level credential removal.

### Network status that must be disclosed

The requested UCU research target is Polygon Amoy (chain ID `80002`). However, the checked-in Laravel blockchain configuration currently defaults to Ethereum Sepolia (chain ID `11155111`). These networks are different. Until the backend, contract deployment, RPC endpoint, and test documentation are consistently configured for Amoy and verified, describe Amoy as the **requested research target**, not as the network currently used by the running application.

The contract address is deployment-specific and must come from the approved environment. Do not put a fabricated address, private key, or other secret in thesis documentation.

## 5. RLS and access-control interpretation

University identity is represented in application records using a university code. Supabase RLS policies exist for selected tables and use trusted Supabase JWT metadata, including role and university-code claims. Laravel API authentication also uses Laravel Sanctum, and the Laravel backend is configured with a Supabase service-role key for selected storage operations.

Consequently, do not claim that Supabase RLS by itself automatically restricts every request made through Laravel. RLS applies when database access is performed under a role/JWT context to which the policies apply; service-role access and Laravel API authorization are separate considerations. UAT should verify institution scoping through the actual request paths and credentials used by the deployed environment.

## 6. UCU UAT focus

For UCU research evaluation, use approved test accounts and non-production test records. Test at least:

1. A UCU student can view only their permitted records.
2. A UCU registrar/admin can create and manage records within the authorized UCU scope.
3. Diploma and TOR examples can be represented and verified as defined by the study protocol.
4. QR lookup returns the intended credential and distinguishes valid, unknown, revoked/removed, and unavailable-service outcomes.
5. Storage and blockchain failures are reported as failures or unavailable states, not as successful issuance.
6. Non-UCU credentials or accounts do not pass an explicitly UCU-only UAT scenario unless the test is intentionally checking cross-institution isolation.
7. Admin review, deletion-request, and audit workflows behave according to the test account's assigned role.

The current application does not establish, by this document alone, an exclusive Diploma/TOR validation rule or a global UCU-only execution lock. Treat exclusivity as the scope and test-data boundary of the UCU study unless a separate, approved software change implements and verifies runtime enforcement.

## 7. Thesis reporting boundary

Report the work as a UCU-focused research/UAT scope within a pilot system that has institution-aware workflows. Do not claim:

- Production onboarding or testing at all Philippine or international universities.
- Polygon Amoy transaction acceptance while the running configuration remains on Sepolia.
- RLS coverage for every table or every Laravel/service-role access path.
- Completed UAT results until test execution and evidence have been recorded.

This document is provided for thesis explanation only. It does not add routes, change runtime configuration, alter database records, or enforce institution/document restrictions.
