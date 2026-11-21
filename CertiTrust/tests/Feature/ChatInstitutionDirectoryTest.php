<?php

namespace Tests\Feature;

use App\Models\University;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ChatInstitutionDirectoryTest extends TestCase
{
    use RefreshDatabase;

    public function test_students_and_university_less_users_can_search_and_message_only_registered_desks(): void
    {
        University::updateOrCreate(['code' => 'UCU'], [
            'university_name' => 'Urdaneta City University',
            'display_name' => 'UCU',
        ]);
        University::updateOrCreate(['code' => 'PSU'], [
            'university_name' => 'Pangasinan State University',
            'display_name' => 'PSU',
        ]);
        University::create([
            'code' => 'NOD',
            'university_name' => 'No Desk University',
            'display_name' => 'NOD',
        ]);

        $ucuDesk = User::create([
            'name' => 'UCU Registrar',
            'email' => 'ucu-desk@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $psuDesk = User::create([
            'name' => 'PSU Registrar',
            'email' => 'psu-desk@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $psuDesk->forceFill(['last_seen_at' => now()])->save();
        $ucuStudent = User::create([
            'name' => 'UCU Graduate',
            'email' => 'ucu-graduate@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        $otherStudent = User::create([
            'name' => 'Private PSU Student',
            'email' => 'private-psu-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        $verifier = User::create([
            'name' => 'External Verifier',
            'email' => 'verifier@example.org',
            'password' => bcrypt('secret'),
            'role' => 'user',
        ]);

        $directory = $this->actingAs($ucuStudent, 'sanctum')
            ->getJson('/api/chat/institutions?search=PSU')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'PSU')
            ->assertJsonPath('data.0.acronym', 'PSU')
            ->assertJsonPath('data.0.university_name', 'Pangasinan State University')
            ->assertJsonPath('data.0.desk_user_id', $psuDesk->id)
            ->assertJsonPath('data.0.verified_registrar_desk', true)
            ->assertJsonPath('data.0.is_active', true);

        $this->assertStringNotContainsString('Private PSU Student', $directory->getContent());
        $this->assertStringNotContainsString((string) $otherStudent->id, $directory->getContent());
        $this->actingAs($ucuStudent, 'sanctum')
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $psuDesk->id,
                'message' => 'I graduated from UCU and need to verify a credential.',
            ])
            ->assertCreated()
            ->assertJsonPath('data.recipient_user_id', $psuDesk->id);

        $this->getJson('/api/chat/messages?with_user_id=' . $psuDesk->id)
            ->assertOk()
            ->assertJsonFragment(['message' => 'I graduated from UCU and need to verify a credential.']);

        $this->postJson('/api/chat/messages', [
            'recipient_user_id' => $otherStudent->id,
            'message' => 'This private student must not be reachable.',
        ])->assertUnprocessable();
        $this->getJson('/api/chat/messages?with_user_id=' . $otherStudent->id)
            ->assertForbidden();

        $this->actingAs($verifier, 'sanctum')
            ->getJson('/api/chat/institutions?search=Pangasinan')
            ->assertOk()
            ->assertJsonPath('data.0.code', 'PSU')
            ->assertJsonPath('data.0.desk_user_id', $psuDesk->id);
        $this->postJson('/api/chat/messages', [
            'recipient_user_id' => $psuDesk->id,
            'message' => 'Please verify this applicant credential.',
        ])->assertCreated()
            ->assertJsonPath('data.university_code', 'PSU');
    }

    public function test_institutional_desks_can_message_other_registered_desks(): void
    {
        University::updateOrCreate(['code' => 'UCU'], [
            'university_name' => 'Urdaneta City University',
            'display_name' => 'UCU',
        ]);
        University::updateOrCreate(['code' => 'PSU'], [
            'university_name' => 'Pangasinan State University',
            'display_name' => 'PSU',
        ]);
        $ucuDesk = User::create([
            'name' => 'UCU Registrar',
            'email' => 'ucu-desk@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $psuDesk = User::create([
            'name' => 'PSU Registrar',
            'email' => 'psu-desk@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);

        $this->actingAs($ucuDesk, 'sanctum')
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $psuDesk->id,
                'message' => 'Cross-university credential verification request.',
            ])
            ->assertCreated();

        $this->actingAs($psuDesk, 'sanctum')
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonFragment([
                'id' => $ucuDesk->id,
                'name' => 'Urdaneta City University',
                'role_label' => 'Verified Registrar Desk',
                'is_institutional_desk' => true,
            ]);

        $this->actingAs($psuDesk, 'sanctum')
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $ucuDesk->id,
                'message' => 'We received the cross-university request.',
            ])
            ->assertCreated();
    }
}
