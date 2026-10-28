<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use GuzzleHttp\Promise\Utils;
use RuntimeException;
use Web3p\EthereumTx\Transaction;
use kornrunner\Keccak;

class BlockchainRegistryService
{
    private const VERIFICATION_RPC_TIMEOUT_SECONDS = 3;

    public function issueCertificate(
        string $sha256,
        string $studentName,
        string $courseName,
        string $issueDate,
    ): array
    {
        $configuration = config('services.certitrust');
        if (!$configuration['enabled']) {
            return ['status' => 'not_configured'];
        }

        $privateKey = preg_replace('/^0x/i', '', trim((string) $configuration['private_key']));
        if (!is_string($privateKey) || !preg_match('/^[a-f0-9]{64}$/i', $privateKey)) {
            throw new RuntimeException('The blockchain signer private key is not configured correctly.');
        }
        $normalizedHash = strtolower(preg_replace('/^0x/i', '', trim($sha256)));
        if (!preg_match('/^[a-f0-9]{64}$/', $normalizedHash)) {
            throw new RuntimeException('The certificate hash must be a 32-byte SHA-256 hex digest.');
        }
        if (!preg_match('/^0x[a-f0-9]{40}$/i', (string) $configuration['contract_address'])) {
            throw new RuntimeException('The blockchain contract address is not configured correctly.');
        }

        $signature = 'issueCertificate(string,string,string,string)';
        $callData = '0x' . substr(Keccak::hash($signature, 256), 0, 8)
            . $this->encodeStringArguments([
                $normalizedHash,
                $studentName,
                $courseName,
                $issueDate,
            ]);

        $sender = $this->addressFromPrivateKey($privateKey);
        $chainId = (int) $configuration['chain_id'];
        $rpcChainId = hexdec($this->rpc($configuration['rpc_url'], 'eth_chainId', []));
        if ((int) $rpcChainId !== $chainId) {
            throw new RuntimeException('The configured blockchain RPC is not on the expected chain ID.');
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
            'network' => $configuration['network'],
        ];
    }

    public function verifyCertificate(string $sha256): array
    {
        return $this->verifyCertificates([$sha256])[0];
    }

    public function verifyCertificates(array $hashes): array
    {
        return $this->verifyCertificatesAttempt($hashes, retryUnavailable: true);
    }

    private function verifyCertificatesAttempt(array $hashes, bool $retryUnavailable): array
    {
        $hashes = array_values($hashes);
        $configuration = config('services.certitrust');
        $results = array_fill(0, count($hashes), [
            'status' => 'unavailable',
            'verified' => false,
        ]);
        if (!$configuration['enabled']) {
            return array_fill(0, count($hashes), [
                'status' => 'not_configured',
                'verified' => false,
            ]);
        }

        $normalizedHashes = [];
        foreach ($hashes as $index => $hash) {
            $normalizedHash = strtolower(preg_replace('/^0x/i', '', trim((string) $hash)));
            if (!preg_match('/^[a-f0-9]{64}$/', $normalizedHash)) {
                $results[$index] = ['status' => 'invalid_hash', 'verified' => false];
                continue;
            }
            $normalizedHashes[$index] = $normalizedHash;
        }

        if (!$normalizedHashes) {
            return $results;
        }

        $rpcUrls = array_values(array_unique(array_filter(array_merge(
            [$configuration['rpc_url']],
            $configuration['rpc_fallback_urls'] ?? [],
        ))));
        if (!$rpcUrls) {
            foreach ($normalizedHashes as $index => $normalizedHash) {
                Log::warning('Blockchain credential verification failed.', [
                    'certificate_hash' => $normalizedHash,
                    'exception' => 'No blockchain RPC endpoints are configured.',
                ]);
            }

            return $results;
        }

        $signature = 'verifyCertificate(string)';
        $requests = [];
        foreach ($normalizedHashes as $hashIndex => $normalizedHash) {
            $callData = '0x' . substr(Keccak::hash($signature, 256), 0, 8)
                . $this->encodeStringArguments([$normalizedHash]);
            foreach ($rpcUrls as $endpointIndex => $rpcUrl) {
                $requests["{$hashIndex}_{$endpointIndex}_chain"] = [
                    'url' => $rpcUrl,
                    'method' => 'eth_chainId',
                    'params' => [],
                ];
                $requests["{$hashIndex}_{$endpointIndex}_verify"] = [
                    'url' => $rpcUrl,
                    'method' => 'eth_call',
                    'params' => [[
                        'to' => $configuration['contract_address'],
                        'data' => $callData,
                    ], 'latest'],
                ];
            }
        }

        try {
            $promises = [];
            $responses = [];
            $pool = new Pool(Http::getFacadeRoot());
            foreach ($requests as $key => $request) {
                try {
                    $pendingRequest = $pool
                        ->as($key)
                        ->connectTimeout(2)
                        ->timeout(self::VERIFICATION_RPC_TIMEOUT_SECONDS)
                        ->acceptJson();
                    $pendingRequest->post($request['url'], [
                        'jsonrpc' => '2.0',
                        'id' => 1,
                        'method' => $request['method'],
                        'params' => $request['params'],
                    ]);
                    $promises[$key] = $pendingRequest->getPromise();
                } catch (\Throwable $exception) {
                    $responses[$key] = $exception;
                }
            }

        } catch (\Throwable $exception) {
            foreach ($normalizedHashes as $index => $normalizedHash) {
                Log::warning('Blockchain credential verification failed.', [
                    'certificate_hash' => $normalizedHash,
                    'exception' => $exception->getMessage(),
                ]);
                $results[$index] = ['status' => 'unavailable', 'verified' => false];
            }

            return $results;
        }

        $parseEndpointResponse = function (array $endpointResponses) use ($configuration): array {
            [$chainResponse, $verificationResponse] = $endpointResponses;
            if (!$chainResponse instanceof Response || !$chainResponse->successful()) {
                throw new RuntimeException('The blockchain RPC did not return a successful chain ID response.');
            }
            $rpcChainId = $chainResponse->json('result');
            if (!is_string($rpcChainId) || hexdec($rpcChainId) !== (int) $configuration['chain_id']) {
                throw new RuntimeException('The blockchain RPC is not on the expected chain ID.');
            }
            if (!$verificationResponse instanceof Response || !$verificationResponse->successful()) {
                throw new RuntimeException('The blockchain RPC did not return a successful contract verification response.');
            }
            $encodedResult = $verificationResponse->json('result');
            if (!is_string($encodedResult)) {
                throw new RuntimeException('The CertiTrust contract returned an invalid verification result.');
            }

            $resultData = strtolower(preg_replace('/^0x/i', '', $encodedResult));
            if (
                !preg_match('/^(?:[a-f0-9]{64})+$/', $resultData)
                || strlen($resultData) < 7 * 64
            ) {
                throw new RuntimeException('The CertiTrust contract returned an invalid verifyCertificate(string) result.');
            }
            $validWord = substr($resultData, 3 * 64, 64);
            if (!preg_match('/^0{63}[01]$/', $validWord)) {
                throw new RuntimeException('The CertiTrust contract returned an invalid credential validity flag.');
            }

            $verified = hexdec($validWord) === 1;

            return [
                'status' => $verified ? 'verified' : 'not_found',
                'verified' => $verified,
                'is_valid' => $verified,
                'network' => $configuration['network'],
            ];
        };

        foreach ($normalizedHashes as $hashIndex => $normalizedHash) {
            $endpointPromises = [];
            foreach ($rpcUrls as $endpointIndex => $_rpcUrl) {
                $chainKey = "{$hashIndex}_{$endpointIndex}_chain";
                $verifyKey = "{$hashIndex}_{$endpointIndex}_verify";
                $endpointPromises[] = Utils::all([
                    $promises[$chainKey] ?? ($responses[$chainKey] ?? null),
                    $promises[$verifyKey] ?? ($responses[$verifyKey] ?? null),
                ])->then($parseEndpointResponse);
            }

            try {
                $results[$hashIndex] = Utils::any($endpointPromises)->wait();
            } catch (\Throwable $exception) {
                Log::warning('Blockchain credential verification failed.', [
                    'certificate_hash' => $normalizedHash,
                    'exception' => $exception->getMessage(),
                ]);
            }
        }

        if ($retryUnavailable) {
            $retryIndexes = [];
            $retryHashes = [];
            foreach ($results as $index => $result) {
                if (
                    ($result['status'] ?? null) === 'unavailable'
                    && isset($normalizedHashes[$index])
                ) {
                    $retryIndexes[] = $index;
                    $retryHashes[] = $normalizedHashes[$index];
                }
            }

            if ($retryHashes !== []) {
                usleep(250_000);
                $retryResults = $this->verifyCertificatesAttempt(
                    $retryHashes,
                    retryUnavailable: false,
                );
                foreach ($retryIndexes as $retryIndex => $originalIndex) {
                    $results[$originalIndex] = $retryResults[$retryIndex];
                }
            }
        }

        return $results;
    }

    private function encodeStringArguments(array $values): string
    {
        $headSize = count($values) * 32;
        $head = '';
        $tail = '';

        foreach ($values as $value) {
            $encodedValue = bin2hex($value);
            $head .= str_pad(dechex($headSize + (int) (strlen($tail) / 2)), 64, '0', STR_PAD_LEFT);
            $tail .= str_pad(dechex(strlen($value)), 64, '0', STR_PAD_LEFT)
                . str_pad($encodedValue, (int) (ceil(strlen($encodedValue) / 64) * 64), '0', STR_PAD_RIGHT);
        }

        return $head . $tail;
    }

    private function rpc(
        string $url,
        string $method,
        array $params,
        int $timeoutSeconds = 25,
    ): string
    {
        $urls = array_values(array_unique(array_filter(array_merge(
            [$url],
            (array) config('services.certitrust.rpc_fallback_urls', []),
        ))));
        $lastFailure = null;

        foreach ($urls as $index => $endpoint) {
            try {
                $response = Http::connectTimeout(min(2, $timeoutSeconds))
                    ->timeout($timeoutSeconds)
                    ->acceptJson()
                    ->post($endpoint, [
                        'jsonrpc' => '2.0',
                        'id' => 1,
                        'method' => $method,
                        'params' => $params,
                    ]);
            } catch (ConnectionException $exception) {
                $lastFailure = $exception;
                if ($index < count($urls) - 1) {
                    Log::warning('Blockchain RPC endpoint was unreachable; trying a fallback.', [
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
            'All configured blockchain RPC endpoints failed: '
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