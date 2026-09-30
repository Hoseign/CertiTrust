<?php

namespace Tests\Feature;

use App\Models\ChatMessage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AdminSubadminManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_bind_replace_and_remove_a_university_subadmin(): void
    {
        $superAdmin = User::firstOrCreate(
            ['email' => 'certitrust256@gmail.com'],
            ['name' => 'CertiTrust Super Admin', 'role' => 'admin', 'university_code' => null, 'password' => bcrypt('secret')]
        );

        $oldEmail = 'oldsubadmin_' . uniqid() . '@ucu.edu';
        $newEmail = 'newsubadmin_' . uniqid() . '@ucu.edu';
        $replacementEmail = 'replacement_' . uniqid() . '@ucu.edu';

        $existingSubadmin = User::firstOrCreate(
            ['email' => $oldEmail],
            ['name' => 'Old UCU Admin', 'role' => 'admin', 'university_code' => 'UCU', 'password' => bcrypt('secret')]
        );

        $this->actingAs($superAdmin, 'sanctum');

        $response = $this->postJson('/api/admin/subadmins', [
            'university_code' => 'UCU',
            'email' => $newEmail,
            'name' => 'New UCU Admin',
        ]);

        $response->assertOk()
            ->assertJsonPath('data.university_code', 'UCU')
            ->assertJsonPath('data.email', $newEmail);

        $this->postJson('/api/admin/subadmins', [
            'university_code' => 'PSU',
            'email' => strtoupper($newEmail),
            'name' => 'Duplicate Admin',
        ])->assertStatus(422)
            ->assertJsonPath('message', 'This email is already in use. Enter another email address.');

        $this->assertDatabaseHas('users', [
            'email' => $newEmail,
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);

        $response = $this->putJson('/api/admin/subadmins/' . $existingSubadmin->id, [
            'email' => $replacementEmail,
            'name' => 'Replacement UCU Admin',
        ]);

        $response->assertOk()
            ->assertJsonPath('data.email', $replacementEmail);

        $this->assertDatabaseHas('users', [
            'id' => $existingSubadmin->id,
            'email' => $replacementEmail,
            'university_code' => 'UCU',
        ]);

        $unbindResponse = $this->deleteJson('/api/admin/subadmins/' . $existingSubadmin->id . '/google');

        $unbindResponse->assertOk()
            ->assertJsonPath('data.google_id', null);

        $this->assertDatabaseHas('users', [
            'id' => $existingSubadmin->id,
            'google_id' => null,
            'university_code' => 'UCU',
        ]);

        $deleteResponse = $this->deleteJson('/api/admin/subadmins/' . $existingSubadmin->id);

        $deleteResponse->assertOk();
        $this->assertDatabaseMissing('users', [
            'id' => $existingSubadmin->id,
        ]);

        $historyResponse = $this->getJson('/api/admin/history');

        $historyResponse->assertOk()
            ->assertJsonFragment(['action' => 'updated_subadmin'])
            ->assertJsonFragment(['action' => 'removed_google_binding'])
            ->assertJsonFragment(['action' => 'deleted_subadmin']);
    }

    public function test_google_login_rejects_unregistered_accounts_until_explicitly_created(): void
    {
        Http::fake([
            'https://www.googleapis.com/oauth2/v3/userinfo' => Http::response([
                'email' => 'demo.user@gmail.com',
                'email_verified' => true,
                'name' => 'Demo User',
                'sub' => 'demo-user-123',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'access_token' => 'fake-access-token',
        ]);

        $response->assertStatus(403)
            ->assertJsonPath('message', 'This Google account is not registered in CertiTrust yet. Only the Super Admin is seeded by default; all other accounts must be created by the system admin.');

        $this->assertDatabaseMissing('users', [
            'email' => 'demo.user@gmail.com',
        ]);
    }

    public function test_issued_student_can_sign_in_and_verify_their_credential_by_hash(): void
    {
        Http::fake([
            'https://www.googleapis.com/oauth2/v3/userinfo' => Http::response([
                'email' => 'student@example.edu',
                'email_verified' => true,
                'name' => 'Issued Student',
                'sub' => 'issued-student-123',
            ], 200),
        ]);

        $hash = str_repeat('a', 64);
        DB::table('certificates')->insert([
            'certificate_code' => 'CERT-ISSUED123',
            'recipient_name' => 'Issued Student',
            'course_or_event' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-09-30',
            'status' => 'Verified',
            'student_id' => '20260002',
            'student_name' => 'Issued Student',
            'student_email' => 'Student@Example.edu',
            'email' => 'Student@Example.edu',
            'degree' => 'BSIT',
            'cert_hash' => $hash,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $login = $this->postJson('/api/auth/google', [
            'access_token' => 'valid-access-token',
        ]);

        $this->assertSame(200, $login->status(), $login->getContent());
        $login->assertOk()
            ->assertJsonPath('email', 'student@example.edu')
            ->assertJsonPath('role', 'student')
            ->assertJsonPath('has_certificate', true);

        $this->assertDatabaseHas('users', [
            'email' => 'student@example.edu',
            'role' => 'student',
            'university_code' => 'PSU',
            'google_id' => 'issued-student-123',
        ]);

        $this->getJson('/api/certificates/' . strtoupper($hash))
            ->assertOk()
            ->assertJsonPath('data.student_id', '20260002');

        $this->withToken($login->json('token'))
            ->postJson('/api/auth/verify-student', [
                'email' => 'STUDENT@example.edu',
                'student_id' => '20260002',
            ])
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('certificate.cert_hash', $hash);
    }

    public function test_batch_issuance_rejects_duplicate_student_ids_but_allows_duplicate_names(): void
    {
        $admin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $this->actingAs($admin, 'sanctum');

        $credential = static fn (
            string $studentId,
            string $hash,
            string $email,
            ?string $diplomaUrl = null,
        ): array => [
            'student_id' => $studentId,
            'student_name' => 'Alex Student',
            'student_email' => $email,
            'degree' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-09-30',
            'cert_hash' => strlen($hash) === 64 ? $hash : str_repeat($hash, 64),
            'diploma_url' => $diplomaUrl,
        ];

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260002', 'a', 'alex-one@example.edu'),
                $credential(' 20260002 ', 'b', 'alex-two@example.edu'),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Student ID "20260002" is repeated in this batch and already belongs to Alex Student (Student ID 20260002).');

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260002', 'c', 'alex-one@example.edu'),
                $credential('20260003', 'd', 'alex-two@example.edu'),
            ],
        ])->assertCreated()
            ->assertJsonPath('count', 2);

        $this->assertDatabaseHas('certificates', [
            'student_id' => '20260002',
            'university_code' => 'PSU',
        ]);

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260002', 'h', 'alex-three@example.edu'),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Student ID "20260002" already belongs to Alex Student (Student ID 20260002). Enter a unique Student ID.');

        $this->postJson('/api/certificates/batch', [
            'certificates' => [$credential('20260004', 'e', 'alex-one@example.edu')],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'A Google email is already linked to a student or administrator account. Use a unique email.');

        $duplicateEmailBatch = $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260004', 'f', 'same@example.edu'),
                $credential('20260005', 'g', 'SAME@example.edu'),
            ],
        ]);
        $duplicateEmailBatch->assertStatus(422)
            ->assertJsonPath('message', 'A Google email is repeated in this batch. Each student must use a unique email.');

        $hash = hash('sha256', 'actual diploma file bytes');
        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260006', $hash, 'hash-check@example.edu'),
            ],
        ])->assertCreated();

        $this->getJson('/api/certificates/' . $hash)
            ->assertOk()
            ->assertJsonPath('data.cert_hash', $hash)
            ->assertJsonPath('data.student_id', '20260006');

        $diplomaUrl = 'https://storage.example/diplomas/used-diploma.jpg';
        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260007', 'j', 'file-owner@example.edu', $diplomaUrl),
            ],
        ])->assertCreated();

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260008', 'k', 'file-reuse@example.edu', $diplomaUrl),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Diploma image "used-diploma.jpg" already belongs to Alex Student (Student ID 20260007). Choose another image file.');
    }

    public function test_chat_presence_and_delete_for_me_work_for_school_users(): void
    {
        $admin = User::firstOrCreate(
            ['email' => 'chatadmin_' . uniqid() . '@ucu.edu'],
            ['name' => 'Chat Admin', 'role' => 'admin', 'university_code' => 'UCU', 'password' => bcrypt('secret')]
        );

        $student = User::firstOrCreate(
            ['email' => 'chatstudent_' . uniqid() . '@ucu.edu'],
            ['name' => 'Chat Student', 'role' => 'student', 'university_code' => 'UCU', 'password' => bcrypt('secret')]
        );

        DB::table('certificates')->insert([
            'certificate_code' => 'CERT-CHAT' . strtoupper(uniqid()),
            'recipient_name' => $student->name,
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-09-30',
            'status' => 'Verified',
            'student_id' => 'CHAT-' . $student->id,
            'student_name' => $student->name,
            'student_email' => $student->email,
            'email' => $student->email,
            'degree' => 'BSIT',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->actingAs($admin, 'sanctum');
        $admin->forceFill(['last_seen_at' => now()])->save();

        $message = ChatMessage::create([
            'user_id' => $admin->id,
            'recipient_user_id' => $student->id,
            'university_code' => 'UCU',
            'sender_email' => $admin->email,
            'sender_name' => $admin->name,
            'message' => 'Hello from admin',
            'deleted_by' => [],
        ]);

        $presenceResponse = $this->getJson('/api/chat/presence');
        $presenceResponse->assertOk()
            ->assertJsonFragment(['id' => $student->id]);

        $deleteResponse = $this->deleteJson('/api/chat/messages/' . $message->id . '?mode=me');
        $deleteResponse->assertOk();

        $conversationResponse = $this->getJson('/api/chat/messages?student_id=' . $student->id);
        $conversationResponse->assertOk();
        $this->assertSame([], $conversationResponse->json('data'));
    }

    public function test_student_reports_and_super_admin_reply_and_approves_deletion_requests(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $admin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $student = User::create([
            'name' => 'Test Student',
            'email' => 'test-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        $certificate = \App\Models\Certificate::create([
            'certificate_code' => 'CERT-REPORT-TEST',
            'recipient_name' => 'Test Student',
            'student_name' => 'Test Student',
            'student_id' => '20260077',
            'student_email' => $student->email,
            'email' => $student->email,
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-09-30',
            'status' => 'Verified',
            'cert_hash' => str_repeat('c', 64),
        ]);

        $this->actingAs($student, 'sanctum');
        $contacts = $this->getJson('/api/chat/contacts')->assertOk();
        $superAdminContact = collect($contacts->json('data'))
            ->firstWhere('id', $superAdmin->id);
        $this->assertNotNull($superAdminContact);
        $this->assertTrue($superAdminContact['is_report_contact']);

        $report = $this->postJson('/api/chat/messages', [
            'recipient_user_id' => $superAdmin->id,
            'message' => 'I need help with my issued credential.',
            'is_report' => true,
        ])->assertCreated()
            ->assertJsonPath('data.is_report', true);

        $this->postJson('/api/user/profile', [
            'profile_icon' => 'girl',
        ])->assertOk()
            ->assertJsonPath('profile_icon', 'girl');

        $this->actingAs($superAdmin, 'sanctum');
        $superAdminContacts = $this->getJson('/api/chat/contacts')->assertOk();
        $this->assertNotNull(collect($superAdminContacts->json('data'))
            ->firstWhere('id', $student->id));

        $this->postJson('/api/chat/messages', [
            'recipient_user_id' => $student->id,
            'message' => 'I received your report and will review it.',
            'reply_to_id' => $report->json('data.id'),
        ])->assertCreated()
            ->assertJsonPath('data.reply_to_id', $report->json('data.id'));

        $this->actingAs($admin, 'sanctum');
        $deletionRequest = $this->postJson('/api/certificates/' . $certificate->id . '/deletion-request', [
            'reason' => 'Credential was issued in error.',
        ])->assertCreated();
        $requestId = $deletionRequest->json('data.id');
        $this->assertDatabaseHas('certificates', ['id' => $certificate->id]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/admin/certificate-deletion-requests/' . $requestId, [
                'decision' => 'approved',
            ])->assertForbidden();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/certificate-deletion-requests/' . $requestId, [
                'decision' => 'approved',
                'reviewer_note' => 'Confirmed duplicate issuance.',
            ])->assertOk()
            ->assertJsonPath('data.status', 'approved');

        $this->assertDatabaseMissing('certificates', ['id' => $certificate->id]);
        $this->assertDatabaseHas('certificate_deletion_requests', [
            'id' => $requestId,
            'student_id' => '20260077',
            'status' => 'approved',
        ]);
        $this->assertTrue(ChatMessage::where('user_id', $superAdmin->id)
            ->where('recipient_user_id', $admin->id)
            ->where('message', 'like', '%Deletion request%approved%')
            ->exists());
    }
}
