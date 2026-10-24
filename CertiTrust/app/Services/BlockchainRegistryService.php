<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Web3p\EthereumTx\Transaction;
use kornrunner\Keccak;

class BlockchainRegistryService
{
    public function issueCertificate(string $documentId, string $studentId, string $sha256): array
    {
        $configuration = config('services.certitrust');
        if (!$configuration['enabled']) {
            return ['status' => 'not_configured'];
        }

        $privateKey = preg_replace('/^0x/i', '', trim($configuration['private_key']));
        if (!preg_match('/^[a-f0-9]{64}$/i', $privateKey)) {
            throw new RuntimeException('The Polygon signer private key is not configured correctly.');
        }
        $normalizedHash = strtolower(preg_replace('/^0x/i', '', trim($sha256)));
        if (!preg_match('/^[a-f0-9]{64}$/', $normalizedHash)) {
            throw new RuntimeException('The certificate hash must be a 32-byte SHA-256 hex digest.');
        }
        if (!preg_match('/^0x[a-f0-9]{40}$/i', (string) $configuration['contract_address'])) {
            throw new RuntimeException('The Polygon contract address is not configured correctly.');
        }

        $abiPath = base_path($configuration['abi_path']);
        if (!is_file($abiPath)) {
            throw new RuntimeException('The CertiTrust contract ABI file was not found.');
        }
        $abi = json_decode(file_get_contents($abiPath), true, flags: JSON_THROW_ON_ERROR);
        $issueFunction = collect($abi)->first(
            fn (array $item) => ($item['type'] ?? null) === 'function'
                && ($item['name'] ?? null) === 'issueCertificate'
        );
        if (!$issueFunction || count($issueFunction['inputs'] ?? []) !== 3) {
            throw new RuntimeException('The configured ABI does not contain issueCertificate(bytes32,bytes32,bytes32).');
        }

        $signature = $issueFunction['name'] . '('
            . implode(',', array_column($issueFunction['inputs'], 'type'))
            . ')';
        $documentIdHash = Keccak::hash($documentId, 256);
            $studentIdHash = hash_hmac('sha256', $studentId, (string) config('app.key'));
        $callData = '0x' . substr(Keccak::hash($signature, 256), 0, 8)
            . $documentIdHash
            . $studentIdHash
            . $normalizedHash;

        $sender = $this->addressFromPrivateKey($privateKey);
        $chainId = (int) $configuration['chain_id'];
        $rpcChainId = hexdec($this->rpc($configuration['rpc_url'], 'eth_chainId', []));
        if ((int) $rpcChainId !== $chainId) {
            throw new RuntimeException('The configured Polygon RPC is not on the expected chain ID.');
        }
        $ownerCall = '0x' . substr(Keccak::hash('owner()', 256), 0, 8);
        $ownerOutput = $this->rpc($configuration['rpc_url'], 'eth_call', [[
            'to' => $configuration['contract_address'],
            'data' => $ownerCall,
        ], 'latest']);
        $contractOwner = '0x' . substr($ownerOutput, -40);
        if (strtolower($contractOwner) !== strtolower($sender)) {
            throw new RuntimeException('The configured signer is not the deployed contract owner.');
        }

        $transactionRequest = [
            'from' => $sender,
            'to' => $configuration['contract_address'],
            'data' => $callData,
            'value' => '0x0',
        ];
        $nonce = $this->rpc($configuration['rpc_url'], 'eth_getTransactionCount', [$sender, 'pending']);
        $gasPrice = $this->rpc($configuration['rpc_url'], 'eth_gasPrice', []);
        $estimatedGas = hexdec($this->rpc($configuration['rpc_url'], 'eth_estimateGas', [$transactionRequest]));

        $transaction = new Transaction([
            'nonce' => $nonce,
            'gasPrice' => $gasPrice,
            'gas' => '0x' . dechex((int) ceil($estimatedGas * 1.2)),
            'to' => $configuration['contract_address'],
            'value' => '0x0',
            'chainId' => $chainId,
            'data' => $callData,
        ]);
        $rawTransaction = (string) $transaction->sign($privateKey);
        if (!str_starts_with($rawTransaction, '0x')) {
            $rawTransaction = '0x' . $rawTransaction;
        }

        $transactionHash = $this->rpc(
            $configuration['rpc_url'],
            'eth_sendRawTransaction',
            [$rawTransaction],
        );

        return [
            'status' => 'submitted',
            'transaction_hash' => $transactionHash,
            'network' => 'polygon-amoy',
        ];
    }

    public function verifyCertificate(string $documentId, string $sha256): array
    {
        $configuration = config('services.certitrust');
        if (!$configuration['enabled']) {
            return ['status' => 'not_configured', 'verified' => false];
        }

        $normalizedHash = strtolower(preg_replace('/^0x/i', '', trim($sha256)));
        if (!preg_match('/^[a-f0-9]{64}$/', $normalizedHash)) {
            return ['status' => 'invalid_hash', 'verified' => false];
        }

        try {
            $signature = 'verifyCertificate(bytes32,bytes32)';
            $callData = '0x' . substr(Keccak::hash($signature, 256), 0, 8)
                . Keccak::hash($documentId, 256)
                . $normalizedHash;
            $encodedResult = $this->rpc($configuration['rpc_url'], 'eth_call', [[
                'to' => $configuration['contract_address'],
                'data' => $callData,
            ], 'latest']);
            $verified = hexdec(substr($encodedResult, -2)) === 1;

            return [
                'status' => $verified ? 'verified' : 'not_found',
                'verified' => $verified,
                'network' => 'polygon-amoy',
            ];
        } catch (\Throwable $exception) {
            Log::warning('Polygon credential verification failed.', [
                'document_id' => $documentId,
                'exception' => $exception->getMessage(),
            ]);

            return ['status' => 'unavailable', 'verified' => false];
        }
    }

    private function rpc(string $url, string $method, array $params): string
    {
        $urls = array_values(array_unique(array_filter(array_merge(
            [$url],
            (array) config('services.certitrust.rpc_fallback_urls', []),
        ))));
        $lastFailure = null;

        foreach ($urls as $index => $endpoint) {
            try {
                $response = Http::timeout(25)->acceptJson()->post($endpoint, [
                    'jsonrpc' => '2.0',
                    'id' => 1,
                    'method' => $method,
                    'params' => $params,
                ]);
            } catch (ConnectionException $exception) {
                $lastFailure = $exception;
                if ($index < count($urls) - 1) {
                    Log::warning('Polygon Amoy RPC endpoint was unreachable; trying a fallback.', [
                        'method' => $method,
                        'endpoint_index' => $index,
                    ]);
                }
                continue;
            }

            if (!$response->successful()) {
                $lastFailure = new RuntimeException(
                    "Polygon RPC returned HTTP {$response->status()}."
                );
                continue;
            }

            $payload = $response->json();
            if (isset($payload['error'])) {
                throw new RuntimeException($payload['error']['message'] ?? 'Polygon RPC request failed.');
            }
            if (!is_array($payload) || !array_key_exists('result', $payload)) {
                $lastFailure = new RuntimeException('Polygon RPC returned an invalid response.');
                continue;
            }

            return (string) $payload['result'];
        }

        throw new RuntimeException(
            'All configured Polygon Amoy RPC endpoints failed: '
                . ($lastFailure?->getMessage() ?? 'no RPC endpoints are configured.'),
            previous: $lastFailure,
        );
    }

    private function addressFromPrivateKey(string $privateKey): string
    {
        $key = (new \Elliptic\EC('secp256k1'))->keyFromPrivate($privateKey, 'hex');
        $publicKey = $key->getPublic(false, 'hex');
        if (str_starts_with(strtolower($publicKey), '0x')) {
            $publicKey = substr($publicKey, 2);
        }
        $address = substr(Keccak::hash(hex2bin(substr($publicKey, 2)), 256), -40);

        return '0x' . $address;
    }
}