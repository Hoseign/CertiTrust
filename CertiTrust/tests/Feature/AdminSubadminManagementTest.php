<?php

namespace Tests\Feature;

use App\Models\ChatMessage;
use App\Models\User;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AdminSubadminManagementTest extends TestCase
{
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
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'aud' => 'test-client-id',
                'azp' => 'test-client-id',
                'email' => 'demo.user@gmail.com',
                'email_verified' => true,
                'name' => 'Demo User',
                'sub' => 'demo-user-123',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'fake-token',
        ]);

        $response->assertStatus(403)
            ->assertJsonPath('message', 'This Google account is not registered in CertiTrust yet. Only the Super Admin is seeded by default; all other accounts must be created by the system admin.');

        $this->assertDatabaseMissing('users', [
            'email' => 'demo.user@gmail.com',
        ]);
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
