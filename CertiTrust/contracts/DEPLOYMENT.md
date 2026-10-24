# CertiTrust Ethereum Sepolia Deployment

## Compile And Deploy With Remix

1. Create a dedicated test wallet for the CertiTrust signer. Never use a personal wallet or a wallet holding real assets. Fund it with Sepolia test ETH from an official faucet.
2. Open Remix IDE and use `CertiTrust.sol` from this folder.
3. In Solidity Compiler, select a `0.8.20` or newer `0.8.x` compiler, compile, and inspect the ABI and bytecode.
4. In MetaMask, select Ethereum Sepolia (chain ID `11155111`). In Remix Deploy & Run, select `Injected Provider - MetaMask`, choose `CertiTrust`, then deploy. The deploying account becomes the contract owner.
5. Copy the deployed contract address. Keep the signer wallet private key out of source control and out of Flutter/web builds.

## Configure Laravel

Set these values in the Laravel `.env` locally and in Render's environment settings. The configured contract must implement `CertiTrust.sol`. `CERTITRUST_SIGNER_PRIVATE_KEY` must belong to that contract's owner and must be a dedicated, test-funded Sepolia key. The supplied deployed contract reports owner `0x4C344f061E71be1cDcA5543507E152E7Ff522593`; the signer address derived from the configured private key must match.

```dotenv
CERTITRUST_CHAIN_ENABLED=false
CERTITRUST_RPC_URL=https://rpc.sepolia.org
CERTITRUST_RPC_FALLBACK_URLS=https://ethereum-sepolia-rpc.publicnode.com,https://sepolia.drpc.org,https://1rpc.io/sepolia
CERTITRUST_CHAIN_ID=11155111
CERTITRUST_NETWORK=ethereum-sepolia
CERTITRUST_CONTRACT_ADDRESS=0xE19411e7df13f0b11d86d629b044c534b453af15
CERTITRUST_SIGNER_PRIVATE_KEY=YOUR_TEST_WALLET_PRIVATE_KEY
```

The service tries `CERTITRUST_RPC_URL` first, then each comma-separated URL in `CERTITRUST_RPC_FALLBACK_URLS` if the endpoint is unreachable or returns an HTTP failure. If `https://rpc.sepolia.org` is unavailable, the configured PublicNode and dRPC endpoints are fallbacks; public RPC services can rate-limit requests, so use a provider-issued Sepolia URL if needed.

Keep `CERTITRUST_CHAIN_ENABLED=false` until the owner private key is configured securely in the backend environment and funded with Sepolia test ETH. Then set it to `true` locally and in Render. Never commit `.env`, paste a private key into chat, or put the signer key in a React `VITE_*` or Flutter `--dart-define` variable. After changing Render environment values, restart/redeploy the service.

## What The Integration Does

The React and Flutter clients submit certificate issuance to the existing authenticated Laravel batch endpoint. Laravel stores the record in PostgreSQL, submits `issueCertificate(string,string,string,string)` to Ethereum Sepolia, then saves the transaction hash and `blockchain_status` on the certificate row. The public certificate/QR lookup calls the deployed contract's `verifyCertificate(string)` method with the normalized SHA-256 hash and reads the method's fourth return value as the on-chain validity flag in `blockchain_verification`.

`submitted` means the RPC accepted the transaction and returned a transaction hash; it does not by itself mean the transaction has been mined. Open the hash on Sepolia Etherscan to inspect confirmation. Database issuance remains available if chain anchoring is disabled or temporarily unavailable, and its response reports that state.

## Local Checks And Builds

```powershell
Push-Location .\CertiTrust
npx --yes solc@0.8.30 --abi -o .\contracts\build .\contracts\CertiTrust.sol
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