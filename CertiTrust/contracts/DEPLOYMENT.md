# CertiTrust Polygon Amoy Deployment

## Compile And Deploy With Remix

1. Create a dedicated test wallet for the CertiTrust signer. Never use a personal wallet or a wallet holding real assets. Fund it with Polygon Amoy test MATIC from an official faucet.
2. Open Remix IDE and create `CertiTrustRegistry.sol` using the source in this folder.
3. In Solidity Compiler, select a `0.8.20` or newer `0.8.x` compiler, compile, and inspect the ABI and bytecode.
4. In MetaMask, add Polygon Amoy (chain ID `80002`) and select it. In Remix Deploy & Run, select `Injected Provider - MetaMask`, choose `CertiTrustRegistry`, then deploy. The deploying account becomes the contract owner.
5. Copy the deployed contract address. Keep the signer wallet private key out of source control and out of Flutter/web builds.
6. Copy the ABI JSON array from Remix into `CertiTrust/contracts/build/contracts_CertiTrustRegistry_sol_CertiTrustRegistry.abi`. The Laravel service reads this ABI file to validate the configured contract interface.

## Configure Laravel

Set these values in the Laravel `.env` locally and in Render's environment settings. `CERTITRUST_SIGNER_PRIVATE_KEY` must belong to the contract owner from step 4, and must be a dedicated, test-funded Amoy key.

```dotenv
CERTITRUST_CHAIN_ENABLED=true
POLYGON_AMOY_RPC_URL=https://polygon-amoy-bor-rpc.publicnode.com
POLYGON_AMOY_RPC_FALLBACK_URLS=https://rpc-amoy.polygon.technology/
POLYGON_AMOY_CHAIN_ID=80002
CERTITRUST_CONTRACT_ADDRESS=0xYOUR_DEPLOYED_CONTRACT_ADDRESS
CERTITRUST_SIGNER_PRIVATE_KEY=YOUR_TEST_WALLET_PRIVATE_KEY
CERTITRUST_CONTRACT_ABI_PATH=contracts/build/contracts_CertiTrustRegistry_sol_CertiTrustRegistry.abi
```

The service tries `POLYGON_AMOY_RPC_URL` first, then each comma-separated URL in `POLYGON_AMOY_RPC_FALLBACK_URLS` if the endpoint is unreachable or returns an HTTP failure. Public RPC services can rate-limit requests; use a provider-issued Amoy URL if needed.

Never commit `.env`, paste a private key into chat, or put the signer key in a React `VITE_*` or Flutter `--dart-define` variable. Fund the signer with Amoy test MATIC. After changing Render environment values, restart/redeploy the service.

## What The Integration Does

The React and Flutter clients submit certificate issuance to the existing authenticated Laravel batch endpoint. Laravel stores the record in PostgreSQL, submits `issueCertificate` to Polygon Amoy, then saves the transaction hash and `blockchain_status` on the certificate row. The public certificate/QR lookup calls the contract's view function and includes `blockchain_verification` in its response.

`submitted` means the RPC accepted the transaction and returned a transaction hash; it does not by itself mean the transaction has been mined. Open the hash on PolygonScan Amoy to inspect confirmation. Database issuance remains available if chain anchoring is disabled or temporarily unavailable, and its response reports that state.

## Local Checks And Builds

```powershell
# Compile with the backend as the current directory so solc's output name matches CERTITRUST_CONTRACT_ABI_PATH.
Push-Location .\CertiTrust
npx --yes solc@0.8.30 --abi -o .\contracts\build .\contracts\CertiTrustRegistry.sol
Pop-Location
Push-Location .\CertiTrust
php artisan migrate --force
Pop-Location

Push-Location .\certitrust_mobile
flutter pub get
flutter build apk --debug --dart-define=CERTITRUST_API_URL=https://certitrust-yhzl.onrender.com/api
flutter build web --release --dart-define=CERTITRUST_API_URL=https://certitrust-yhzl.onrender.com/api
Pop-Location

Push-Location .\certitrust_web
$env:VITE_API_BASE_URL = "https://certitrust-yhzl.onrender.com/api"
npm run build
Pop-Location
```

For local Flutter Web/desktop use `--dart-define=CERTITRUST_API_URL=http://localhost:8000/api`. For the Android emulator use `http://10.0.2.2:8000/api`; for a physical device, use the development machine's LAN IP. The Laravel CORS origin must include the browser frontend origin.

## Supabase RLS Note

See `database/rls/certificates_rls.sql`. Those policies use Supabase Auth JWT claims. Current web/mobile API calls use Laravel Sanctum bearer tokens, which are not Supabase Auth JWTs; continue to authorize those calls in Laravel. Public verifiers call the safe `verify_certificate_hash` function rather than receiving anonymous table-level `SELECT` access.