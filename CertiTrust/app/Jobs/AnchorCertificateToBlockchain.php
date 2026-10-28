<?php

namespace App\Jobs;

use App\Models\Certificate;
use App\Services\BlockchainRegistryService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Throwable;

class AnchorCertificateToBlockchain implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1;

    public int $timeout = 120;

    public function __construct(public int $certificateId)
    {
    }

    public function handle(BlockchainRegistryService $blockchain): void
    {
        $certificate = Certificate::find($this->certificateId);
        if (!$certificate || $certificate->blockchain_status !== 'pending') {
            return;
        }

        try {
            $result = $blockchain->issueCertificate(
                (string) $certificate->cert_hash,
                (string) ($certificate->student_name ?: $certificate->recipient_name),
                (string) $certificate->degree,
                (string) $certificate->issue_date,
            );
        } catch (Throwable $exception) {
            Log::warning('Blockchain credential submission failed.', [
                'certificate_id' => $certificate->id,
                'exception' => $exception->getMessage(),
            ]);
            $result = [
                'status' => 'failed',
                'error' => 'Blockchain submission failed. The certificate remains in the application database.',
            ];
        }

        $certificate->forceFill([
            'blockchain_status' => $result['status'],
            'blockchain_tx_hash' => $result['transaction_hash'] ?? null,
            'blockchain_network' => $result['network'] ?? null,
            'blockchain_error' => $result['error'] ?? null,
        ])->save();
    }
}
