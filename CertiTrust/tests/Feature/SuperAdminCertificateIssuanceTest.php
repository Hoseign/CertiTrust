<?php

namespace Tests\Feature;

use App\Jobs\AnchorCertificateToBlockchain;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class SuperAdminCertificateIssuanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_superadmin_can_issue_certificates_for_a_selected_university(): void
    {
        config(['services.certitrust.enabled' => true]);
        Queue::fake();

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
            ->assertJsonPath('data.0.blockchain_status', 'pending');

        Queue::assertPushed(AnchorCertificateToBlockchain::class, 1);
        $this->assertDatabaseHas('certificates', [
            'student_id' => 'SUPER-ISSUE-1001',
            'university_code' => 'UCU',
            'student_email' => 'taylor-super-issue@example.edu',
            'blockchain_status' => 'pending',
        ]);
    }
}
