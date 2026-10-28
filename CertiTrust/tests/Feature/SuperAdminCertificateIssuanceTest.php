<?php

namespace Tests\Feature;

use App\Models\Certificate;
use App\Models\User;
use App\Services\BlockchainRegistryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SuperAdminCertificateIssuanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_pending_certificate_can_be_retried_inline_with_database_queue_configured(): void
    {
        config(['queue.default' => 'database']);

        $certificate = Certificate::create([
            'certificate_code' => 'CERT-PENDING-RETRY',
            'student_id' => 'PENDING-RETRY-1001',
            'student_name' => 'Pending Student',
            'recipient_name' => 'Pending Student',
            'degree' => 'Bachelor of Science',
            'course_or_event' => 'Bachelor of Science',
            'university_code' => 'UCU',
            'issue_date' => '2026-10-28',
            'cert_hash' => str_repeat('c', 64),
            'status' => 'Verified',
            'blockchain_status' => 'pending',
        ]);

        $this->mock(BlockchainRegistryService::class)
            ->shouldReceive('issueCertificate')
            ->once()
            ->with(
                str_repeat('c', 64),
                'Pending Student',
                'Bachelor of Science',
                '2026-10-28',
            )
            ->andReturn([
                'status' => 'submitted',
                'transaction_hash' => '0x' . str_repeat('d', 64),
                'network' => 'ethereum-sepolia',
            ]);

        $this->artisan('certificates:anchor-pending', ['--id' => $certificate->id])
            ->expectsOutputToContain('CERT-PENDING-RETRY: submitted')
            ->assertExitCode(0);

        $this->assertDatabaseHas('certificates', [
            'id' => $certificate->id,
            'blockchain_status' => 'submitted',
            'blockchain_tx_hash' => '0x' . str_repeat('d', 64),
        ]);
    }

    public function test_superadmin_can_issue_certificates_for_a_selected_university(): void
    {
        config(['services.certitrust.enabled' => true]);
        config(['queue.default' => 'database']);
        $this->mock(BlockchainRegistryService::class)
            ->shouldReceive('issueCertificate')
            ->once()
            ->with(
                str_repeat('a', 64),
                'Taylor Student',
                'Bachelor of Science in Information Technology',
                '2026-10-24',
            )
            ->andReturn([
                'status' => 'submitted',
                'transaction_hash' => '0x' . str_repeat('b', 64),
                'network' => 'ethereum-sepolia',
            ]);

        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $certificate = [
            'student_id' => 'SUPER-ISSUE-1001',
            'student_name' => 'Taylor Student',
            'student_email' => 'taylor-super-issue@example.edu',
            'degree' => 'Bachelor of Science in Information Technology',
            'university_code' => 'UCU',
            'issue_date' => '2026-10-24',
            'cert_hash' => str_repeat('a', 64),
        ];

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/certificates/validate-batch', [
                'university_code' => 'UCU',
                'certificates' => [$certificate],
            ])
            ->assertOk()
            ->assertJsonPath('additional_degree_candidates', []);

        $this->postJson('/api/certificates/batch', [
            'university_code' => 'UCU',
            'certificates' => [$certificate],
        ])
            ->assertCreated()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('data.0.blockchain_status', 'submitted')
            ->assertJsonPath('data.0.blockchain_tx_hash', '0x' . str_repeat('b', 64));

        $this->assertDatabaseHas('certificates', [
            'student_id' => 'SUPER-ISSUE-1001',
            'university_code' => 'UCU',
            'student_email' => 'taylor-super-issue@example.edu',
            'blockchain_status' => 'submitted',
            'blockchain_tx_hash' => '0x' . str_repeat('b', 64),
        ]);
    }
}
