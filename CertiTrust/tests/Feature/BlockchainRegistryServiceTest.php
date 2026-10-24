<?php

namespace Tests\Feature;

use App\Services\BlockchainRegistryService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BlockchainRegistryServiceTest extends TestCase
{
    public function test_verification_retries_with_the_sepolia_fallback_rpc(): void
    {
        Http::fake([
            'https://primary.example' => function () {
                throw new ConnectionException('Primary RPC could not be reached.');
            },
            'https://fallback.example' => Http::response([
                'jsonrpc' => '2.0',
                'id' => 1,
                'result' => '0xaa36a7',
            ]),
        ]);
        config(['services.certitrust.rpc_fallback_urls' => ['https://fallback.example']]);
        $rpc = new \ReflectionMethod(BlockchainRegistryService::class, 'rpc');
        $result = $rpc->invoke(
            app(BlockchainRegistryService::class),
            'https://primary.example',
            'eth_chainId',
            [],
        );

        Http::assertSent(fn ($request) => $request->url() === 'https://fallback.example');
        $this->assertSame('0xaa36a7', $result);
    }

    public function test_certificate_verification_uses_the_fallback_rpc(): void
    {
        config([
            'services.certitrust.enabled' => true,
            'services.certitrust.rpc_url' => 'https://primary.example',
            'services.certitrust.rpc_fallback_urls' => ['https://fallback.example'],
            'services.certitrust.chain_id' => 11155111,
            'services.certitrust.contract_address' => '0x1111111111111111111111111111111111111111',
        ]);
        Http::fake([
            'https://primary.example' => Http::response(['message' => 'Unavailable'], 503),
            'https://fallback.example' => function ($request) {
                return Http::response([
                    'jsonrpc' => '2.0',
                    'id' => 1,
                    'result' => $request['method'] === 'eth_chainId'
                        ? '0xaa36a7'
                        : '0x' . str_repeat('0', 63) . '1',
                ]);
            },
        ]);

        $result = app(BlockchainRegistryService::class)->verifyCertificate(
            str_repeat('a', 64),
        );

        Http::assertSent(fn ($request) => $request->url() === 'https://primary.example');
        Http::assertSent(fn ($request) => $request->url() === 'https://fallback.example');
        $expectedMappingCall = '0x8f2b91ea'
            . str_pad('20', 64, '0', STR_PAD_LEFT)
            . str_pad('40', 64, '0', STR_PAD_LEFT)
            . str_repeat('61', 64);
        Http::assertSent(fn ($request) => $request->url() === 'https://fallback.example'
            && $request['method'] === 'eth_call'
            && $request['params'][0]['data'] === $expectedMappingCall);
        $this->assertSame('verified', $result['status']);
        $this->assertTrue($result['verified']);
    }

    public function test_certificate_verification_rejects_an_unexpected_chain_id(): void
    {
        config([
            'services.certitrust.enabled' => true,
            'services.certitrust.rpc_url' => 'https://primary.example',
            'services.certitrust.rpc_fallback_urls' => [],
            'services.certitrust.chain_id' => 11155111,
            'services.certitrust.contract_address' => '0x1111111111111111111111111111111111111111',
        ]);
        Http::fake([
            'https://primary.example' => Http::response([
                'jsonrpc' => '2.0',
                'id' => 1,
                'result' => '0x13882',
            ]),
        ]);

        $result = app(BlockchainRegistryService::class)->verifyCertificate(
            str_repeat('a', 64),
        );

        $this->assertSame('unavailable', $result['status']);
        $this->assertFalse($result['verified']);
        Http::assertSentCount(1);
    }

    public function test_issuance_encodes_the_deployed_four_string_function(): void
    {
        config([
            'services.certitrust.enabled' => true,
            'services.certitrust.rpc_url' => 'https://sepolia.example',
            'services.certitrust.rpc_fallback_urls' => [],
            'services.certitrust.chain_id' => 11155111,
            'services.certitrust.network' => 'ethereum-sepolia',
            'services.certitrust.contract_address' => '0x1111111111111111111111111111111111111111',
            'services.certitrust.private_key' => str_repeat('1', 64),
        ]);
        Http::fake([
            'https://sepolia.example' => function ($request) {
                $result = match ($request['method']) {
                    'eth_chainId' => '0xaa36a7',
                    'eth_call' => '0x00000000000000000000000019e7e376e7c213b7e7e7e46cc70a5dd086daff2a',
                    'eth_getTransactionCount' => '0x0',
                    'eth_gasPrice' => '0x3b9aca00',
                    'eth_estimateGas' => '0x5208',
                    'eth_sendRawTransaction' => '0x' . str_repeat('b', 64),
                    default => throw new \RuntimeException('Unexpected RPC method: ' . $request['method']),
                };

                return Http::response(['jsonrpc' => '2.0', 'id' => 1, 'result' => $result]);
            },
        ]);

        $result = app(BlockchainRegistryService::class)->issueCertificate(
            str_repeat('a', 64),
            'Alice Student',
            'Bachelor of Science',
            '2026-10-24',
        );

        $transactionData = null;
        Http::assertSent(function ($request) use (&$transactionData) {
            if ($request['method'] !== 'eth_estimateGas') {
                return false;
            }

            $transactionData = $request['params'][0]['data'];

            return true;
        });
        $this->assertNotNull($transactionData);
        $expectedIssueHead = '0x818a2994'
            . str_pad('80', 64, '0', STR_PAD_LEFT)
            . str_pad('e0', 64, '0', STR_PAD_LEFT)
            . str_pad('120', 64, '0', STR_PAD_LEFT)
            . str_pad('160', 64, '0', STR_PAD_LEFT);
        $this->assertStringStartsWith($expectedIssueHead, $transactionData);
        $this->assertStringContainsString(bin2hex('Alice Student'), $transactionData);
        $this->assertStringContainsString(bin2hex('Bachelor of Science'), $transactionData);
        Http::assertSent(fn ($request) => $request['method'] === 'eth_sendRawTransaction');
        $this->assertSame('submitted', $result['status']);
        $this->assertSame('0x' . str_repeat('b', 64), $result['transaction_hash']);
        $this->assertSame('ethereum-sepolia', $result['network']);
    }
}
