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

        $credential = static fn (string $studentId, string $hash): array => [
            'student_id' => $studentId,
            'student_name' => 'Alex Student',
            'student_email' => 'alex@example.edu',
            'degree' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-09-30',
            'cert_hash' => str_repeat($hash, 64),
        ];

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260002', 'a'),
                $credential(' 20260002 ', 'b'),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'A Student ID is repeated in this batch. Use a unique Student ID for every student.');

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                $credential('20260002', 'c'),
                $credential('20260003', 'd'),
            ],
        ])->assertCreated()
            ->assertJsonPath('count', 2);

        $this->postJson('/api/certificates/batch', [
            'certificates' => [$credential('20260002', 'e')],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'A Student ID is already used by an issued credential. Enter a unique Student ID.');
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
}
