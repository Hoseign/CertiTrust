# CertiTrust Multi-University System Overview

**Project title:** CertiTrust: A Blockchain-Based Digital Identity and Academic Records Verification System  
**Document purpose:** Explain the system-wide design and its institution-aware model for thesis reporting. This file is informational documentation, not machine-readable configuration.

## 1. System overview

CertiTrust is a digital identity and academic-record management and verification system. It combines mobile and web clients with a Laravel API, PostgreSQL-backed data services, document storage, and optional blockchain verification.

The system has institution-aware data and administration workflows. A university code is associated with users, credentials, and university access-control records so authorized workflows can distinguish institutional records. The application includes student, university administrator/subadmin, and Super Admin experiences.

## 2. Current implementation scope versus scalability goal

The architecture is intended to support institution-scoped operation and can be extended for additional higher education institutions through institution registration, account provisioning, data association, and policy configuration.

The checked-in pilot is **not** evidence that any university can already self-onboard or that all universities have been deployed or tested. The repository's project documentation identifies Urdaneta City University (UCU) and Pangasinan State University (PSU) Urdaneta as the pilot institutions. The university table is seeded with UCU and PSU and can also accommodate codes found in existing user/credential data. This should not be described as a completed, automated onboarding service for arbitrary institutions.

Use the phrase **multi-university-capable pilot** or **institution-aware pilot** when describing current scope. Describe support for arbitrary institutions as a scalability goal that requires onboarding and validation, not as a completed deployment.

## 3. Platform components

| Component | Role in the system |
|---|---|
| Flutter mobile application | Mobile access for students and administrators, including credential views and QR scanning on supported platforms. Android APK is the stated mobile delivery target for the UCU research scope. |
| React/Vite web client | Browser-based student, university administrator, and Super Admin interfaces. |
| Laravel 11 API | Backend application workflows, authentication/authorization, credential management, and optional blockchain RPC operations. Laravel Sanctum is used for API tokens. |
| Supabase PostgreSQL | Shared application data service. Selected SQL policies define institution-aware access through trusted Supabase JWT claims. |
| Supabase Storage | Storage for supported diploma files and chat attachments. |
| Ethereum-compatible smart contract/RPC | Optional test-network anchoring and verification. Requires matching network configuration, compatible deployed contract, RPC connectivity, and protected backend signer settings. |

## 4. Institution and role model

University codes are used to associate users, credentials, and access-control settings with an institution. University administrators are expected to manage records within their authorized university scope. Students access their own permitted credential records. Super Admin functions support broader administration across the pilot institutions.

Supabase RLS policies are defined for selected tables and compare trusted JWT role, university code, and Super Admin claims. Laravel also performs API authorization and accesses Supabase using configured backend credentials for relevant operations. These are distinct access paths: a thesis should not imply that RLS automatically governs every Laravel or service-role request. Security and UAT claims should identify the exact path and policy that was tested.

## 5. Main system workflows

### Identity and access

- Users sign in through supported application flows; Google sign-in is available where configured.
- The backend supplies role and university identity used for the appropriate client experience.
- Session restoration, logout/token revocation, and supported account-freeze workflows are available.

### Credential management

- Students view available academic credential records and associated details.
- Authorized university administrators create individual or batch credential records and attach supported diploma documents.
- Credential records retain their institution code and normalized hash used by verification workflows.
- Students or administrators can generate or use QR-based verification paths, as allowed by the application.

### Verification and lifecycle management

- Public or authenticated verification flows look up a credential and present its available status.
- When blockchain anchoring is enabled and correctly configured, the backend submits contract-defined credential hashes/values and retains transaction/network/status information.
- Credential removal uses application-level request/review workflows. Revocation or removal from active use does not erase immutable blockchain history.
- Administrative actions, access changes, and supported chat workflows are available according to role and authorization.

## 6. Privacy and data handling

Credential records and documents are managed through application/database/storage services. The blockchain verification design relies on hashes and contract-defined values rather than placing diploma files or full personal academic records on a public ledger. Public verification should expose only information approved for public display.

Deployment secrets—including Supabase service-role credentials and blockchain signer keys—must remain in protected backend environment configuration and must not be included in public documents, client bundles, or source control.

## 7. Blockchain network status

The repository's current Laravel blockchain defaults describe Ethereum Sepolia (chain ID `11155111`). Polygon Amoy (chain ID `80002`) is a separately requested target and is not interchangeable with Sepolia. Before reporting Amoy as operational, align and verify the backend RPC/network settings, deployed contract address, contract compatibility, test wallet, and explorer evidence.

Blockchain writes are optional/configuration-dependent. A successful API response indicating transaction submission must not be described as mined or confirmed unless the corresponding chain status has been checked.

## 8. Multi-university onboarding considerations

To extend the pilot to another institution, an implementation and deployment would need, at minimum:

1. Register a unique institution code and authoritative display name.
2. Agree on institution identity, domains/contact details, and administrative ownership.
3. Provision and verify university administrators with the correct institution scope.
4. Ensure users and credential records receive the correct university code.
5. Validate Laravel authorization and applicable Supabase RLS claims/policies for that institution.
6. Agree on document types, retention, privacy, and public-verification fields.
7. Configure institution-specific contract/network requirements if institutions do not share one ledger setup.
8. Run cross-institution isolation, access-control, credential, QR, and recovery tests before onboarding real data.

These are onboarding requirements, not a claim that the repository currently provides a self-service onboarding feature. Sample or generic universities should not be presented as real participating institutions unless they have been explicitly configured and approved.

## 9. Testing and reporting boundary

The pilot scope documented in the repository is UCU and PSU Urdaneta. Test execution results must be recorded separately; requirements and test-case descriptions alone are not evidence that tests passed. Browser/device compatibility, production service levels, privacy approvals, and network selection require institution/project-team decisions where they are not established in the repository.

This overview is for thesis explanation. It does not define executable `UniversityConfig` data, modify application behavior, enforce institution isolation, create university accounts, or change blockchain network settings.
