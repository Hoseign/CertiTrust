<?php

namespace App\Console\Commands;

use App\Jobs\AnchorCertificateToBlockchain;
use App\Models\Certificate;
use Illuminate\Console\Command;

class AnchorPendingCertificates extends Command
{
    protected $signature = 'certificates:anchor-pending
        {--id= : Retry one certificate by database ID}
        {--limit=100 : Maximum number of pending certificates to retry}';

    protected $description = 'Submit pending certificates to the configured blockchain inline';

    public function handle(): int
    {
        $query = Certificate::query()
            ->where('blockchain_status', 'pending')
            ->orderBy('id');

        if ($id = $this->option('id')) {
            if (!ctype_digit((string) $id)) {
                $this->error('The certificate ID must be a positive integer.');

                return self::INVALID;
            }

            $query->whereKey((int) $id);
        } else {
            $query->limit(max(1, (int) $this->option('limit')));
        }

        $certificates = $query->get(['id', 'certificate_code']);
        if ($certificates->isEmpty()) {
            $this->info('No pending certificates were found.');

            return self::SUCCESS;
        }

        $this->warn('Retrying pending blockchain submissions inline; this may use Sepolia gas.');
        $failures = 0;

        foreach ($certificates as $certificate) {
            AnchorCertificateToBlockchain::dispatchSync($certificate->id);
            $status = Certificate::query()
                ->whereKey($certificate->id)
                ->value('blockchain_status');

            $this->line("{$certificate->certificate_code}: {$status}");

            if ($status !== 'submitted') {
                $failures++;
            }
        }

        return $failures === 0 ? self::SUCCESS : self::FAILURE;
    }
}
