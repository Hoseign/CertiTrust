<?php

namespace Tests\Feature;

use App\Services\BlockchainRegistryService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BlockchainRegistryServiceTest extends TestCase
{
    public function test_verification_retries_with_the_polygon_amoy_fallback_rpc(): void
    {
        Http::fake([
            'https://primary.example' => function () {
                throw new ConnectionException('Primary RPC could not be reached.');
            },
            'https://fallback.example' => Http::response([
                'jsonrpc' => '2.0',
                'id' => 1,
                'result' => '0x13882',
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
        $this->assertSame('0x13882', $result);
    }

    public function test_certificate_verification_uses_the_fallback_rpc(): void
    {
        config([
            'services.certitrust.enabled' => true,
            'services.certitrust.rpc_url' => 'https://primary.example',
            'services.certitrust.rpc_fallback_urls' => ['https://fallback.example'],
            'services.certitrust.contract_address' => '0x1111111111111111111111111111111111111111',
        ]);
        Http::fake([
            'https://primary.example' => Http::response(['message' => 'Unavailable'], 503),
            'https://fallback.example' => Http::response([
                'jsonrpc' => '2.0',
                'id' => 1,
                'result' => '0x' . str_repeat('0', 63) . '1',
            ]),
        ]);

        $result = app(BlockchainRegistryService::class)->verifyCertificate(
            'CERT-TEST-001',
            str_repeat('a', 64),
        );

        Http::assertSent(fn ($request) => $request->url() === 'https://primary.example');
        Http::assertSent(fn ($request) => $request->url() === 'https://fallback.example');
        $this->assertSame('verified', $result['status']);
        $this->assertTrue($result['verified']);
    }
}
