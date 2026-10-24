<?php

namespace Tests\Feature;

use App\Models\ChatMessage;
use App\Models\Certificate;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AdminSubadminManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_chat_api_preflight_returns_cors_headers_for_local_web_app(): void
    {
        $this->call('OPTIONS', '/api/chat/contacts', [], [], [], [
            'HTTP_ORIGIN' => 'http://localhost:5173',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'GET',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'authorization,content-type,x-requested-with',
        ])->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', 'http://localhost:5173')
            ->assertHeader('Access-Control-Allow-Methods')
            ->assertHeader('Access-Control-Allow-Headers');
    }

    public function test_only_superadmin_can_revoke_a_certificate_and_make_its_qr_unresolvable(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $universityAdmin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-revoke-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $certificate = Certificate::create([
            'certificate_code' => 'PSU-QR-REVOKE-TEST',
            'student_name' => 'Revoked Student',
            'recipient_name' => 'Revoked Student',
            'student_id' => 'PSU-REVOKE-1001',
            'student_email' => 'revoked-student@example.edu',
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('f', 64),
        ]);

        $this->getJson('/api/certificates/PSU-QR-REVOKE-TEST')
            ->assertOk();
        $this->actingAs($universityAdmin, 'sanctum')
            ->deleteJson('/api/admin/certificates/' . $certificate->id)
            ->assertForbidden();

        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/certificates/' . $certificate->id)
            ->assertOk()
            ->assertJsonPath('data.certificate_code', 'PSU-QR-REVOKE-TEST');

        $this->assertDatabaseMissing('certificates', ['id' => $certificate->id]);
        $this->getJson('/api/certificates/PSU-QR-REVOKE-TEST')
            ->assertStatus(410)
            ->assertJsonPath('status', 'removed')
            ->assertJsonPath('message', 'This credential was removed from the database and is no longer valid.');

        $replacement = $this->actingAs($universityAdmin, 'sanctum')
            ->postJson('/api/certificates', [
                'student_id' => 'PSU-REVOKE-1001',
                'student_name' => 'Revoked Student',
                'student_email' => 'revoked-student@example.edu',
                'degree' => 'BSIT',
                'issue_date' => '2026-10-24',
                'cert_hash' => str_repeat('a', 64),
            ])
            ->assertCreated();
        $this->getJson('/api/certificates/' . $replacement->json('data.certificate_code'))
            ->assertOk();
        $this->getJson('/api/certificates/' . str_repeat('a', 64))
            ->assertOk();
    }

    public function test_superadmin_can_purge_accounts_credentials_and_universities(): void
    {
        DB::table('universities')->insert([
            'code' => 'PSUU',
            'university_name' => 'Duplicate PSU Registration',
            'branch_campus' => null,
            'display_name' => 'PSUU',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $subadmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'purge-ucu-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'Student to purge',
            'email' => 'purge-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        $legacyUser = User::create([
            'name' => 'Legacy user to purge',
            'email' => 'purge-legacy-user@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'user',
            'university_code' => 'UCU',
        ]);
        DB::table('university_access_controls')->insert([
            'university_code' => 'UCU',
            'students_frozen' => false,
            'updated_by' => $superAdmin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('junk_items')->insert([
            'record_type' => 'student_account',
            'university_code' => 'UCU',
            'student_name' => 'Old junk student',
            'student_email' => 'old-junk-student@example.edu',
            'source' => 'student_removal_approved',
            'payload' => json_encode(['student' => [], 'certificates' => []]),
            'deleted_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('student_deletion_requests')->insert([
            'student_user_id' => $student->id,
            'requested_by' => $subadmin->id,
            'student_name' => $student->name,
            'student_email' => $student->email,
            'university_code' => 'PSU',
            'status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach ([
            ['code' => 'PURGE-UCU-CREDENTIAL', 'hash' => str_repeat('b', 64), 'university' => 'UCU'],
            ['code' => 'PURGE-PSU-CREDENTIAL', 'hash' => str_repeat('c', 64), 'university' => 'PSU'],
        ] as $credential) {
            Certificate::create([
                'certificate_code' => $credential['code'],
                'student_name' => 'Credential to purge',
                'recipient_name' => 'Credential to purge',
                'student_id' => 'REUSABLE-STUDENT-ID',
                'student_email' => 'purge-student@example.edu',
                'degree' => 'BSIT',
                'course_or_event' => 'BSIT',
                'university_code' => $credential['university'],
                'issue_date' => '2026-06-01',
                'status' => 'Verified',
                'cert_hash' => $credential['hash'],
            ]);
        }

        $this->actingAs($subadmin, 'sanctum')
            ->deleteJson('/api/admin/accounts-and-credentials')
            ->assertForbidden();
        $this->assertDatabaseHas('users', ['id' => $student->id]);

        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/accounts-and-credentials')
            ->assertOk()
            ->assertJsonPath('data.deleted_subadmin_count', 1)
            ->assertJsonPath('data.deleted_student_count', 2)
            ->assertJsonPath('data.deleted_certificate_count', 2)
            ->assertJsonPath('data.deleted_university_count', 3)
            ->assertJsonPath('data.deleted_junk_item_count', 1)
            ->assertJsonPath('data.deleted_student_removal_request_count', 1);

        $this->assertDatabaseHas('users', ['id' => $superAdmin->id]);
        $this->assertDatabaseMissing('users', ['id' => $subadmin->id]);
        $this->assertDatabaseMissing('users', ['id' => $student->id]);
        $this->assertDatabaseMissing('users', ['id' => $legacyUser->id]);
        $this->assertDatabaseMissing('certificates', ['certificate_code' => 'PURGE-UCU-CREDENTIAL']);
        $this->assertDatabaseMissing('universities', ['code' => 'UCU']);
        $this->assertDatabaseMissing('universities', ['code' => 'PSU']);
        $this->assertDatabaseMissing('universities', ['code' => 'PSUU']);
        $this->assertDatabaseMissing('university_access_controls', ['university_code' => 'UCU']);
        $this->assertDatabaseCount('junk_items', 0);
        $this->assertDatabaseCount('student_deletion_requests', 0);
        $this->getJson('/api/certificates/PURGE-UCU-CREDENTIAL')
            ->assertStatus(410)
            ->assertJsonPath('status', 'removed');
        $this->getJson('/api/certificates/' . str_repeat('c', 64))
            ->assertStatus(410)
            ->assertJsonPath('status', 'removed');

        DB::table('universities')->insert([
            'code' => 'PSU',
            'university_name' => 'Pangasinan State University',
            'branch_campus' => null,
            'display_name' => 'PSU',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        User::create([
            'name' => 'Replacement student',
            'email' => 'purge-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        $this->assertDatabaseHas('users', [
            'email' => 'purge-student@example.edu',
            'role' => 'student',
        ]);
    }

    public function test_only_the_university_subadmin_can_remove_a_frozen_student_and_revoke_credentials(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-delete-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'Frozen UCU Student',
            'email' => 'old-ucu-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
            'access_frozen' => true,
            'access_frozen_by' => $superAdmin->id,
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-REVOKE-AFTER-STUDENT-DELETE',
            'student_name' => 'Frozen UCU Student',
            'recipient_name' => 'Frozen UCU Student',
            'student_id' => 'UCU-DELETE-1001',
            'student_email' => 'old-ucu-student@example.edu',
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('e', 64),
        ]);
        $this->getJson('/api/certificates/CERT-REVOKE-AFTER-STUDENT-DELETE')
            ->assertOk()
            ->assertJsonPath('data.student_id', 'UCU-DELETE-1001');

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/subadmins')
            ->assertOk()
            ->assertJsonPath('data.0.frozen_students.0.id', $student->id)
            ->assertJsonPath('data.0.frozen_students.0.email', $student->email);

        $this->deleteJson('/api/admin/students/' . $student->id)
            ->assertForbidden();

        $this->actingAs($ucuAdmin, 'sanctum')
            ->deleteJson('/api/admin/students/' . $student->id)
            ->assertStatus(202)
            ->assertJsonPath('data.status', 'pending');

        $requestId = DB::table('student_deletion_requests')
            ->where('student_user_id', $student->id)
            ->value('id');
        $this->assertDatabaseHas('users', ['id' => $student->id]);

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/student-deletion-requests/' . $requestId, [
                'decision' => 'approved',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'approved');

        $this->assertDatabaseMissing('users', ['id' => $student->id]);
        $this->assertDatabaseMissing('certificates', [
            'cert_hash' => str_repeat('e', 64),
        ]);
        $junkItem = DB::table('junk_items')
            ->where('record_type', 'student_account')
            ->where('student_user_id', $student->id)
            ->first();
        $this->assertNotNull($junkItem);
        $this->assertSame(
            'CERT-REVOKE-AFTER-STUDENT-DELETE',
            json_decode($junkItem->payload, true)['certificates'][0]['certificate_code'],
        );
        $this->getJson('/api/certificates/CERT-REVOKE-AFTER-STUDENT-DELETE')
            ->assertStatus(410)
            ->assertJsonPath('status', 'removed');
        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/subadmins')
            ->assertOk()
            ->assertJsonCount(0, 'data.0.frozen_students');
    }

    public function test_removing_subadmins_moves_their_accounts_and_students_into_the_shared_junk_bin(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $students = [];
        foreach ([
            ['code' => 'UCU', 'prefix' => 'UcuUser'],
            ['code' => 'PSU', 'prefix' => 'PsuUser'],
        ] as $university) {
            $admin = User::create([
                'name' => $university['code'] . ' Admin',
                'email' => strtolower($university['code']) . '-junk-admin@example.edu',
                'password' => bcrypt('secret'),
                'role' => 'admin',
                'university_code' => $university['code'],
            ]);
            $student = User::create([
                'name' => $university['prefix'] . ' T. Student',
                'email' => strtolower($university['code']) . '-junk-student@example.edu',
                'password' => bcrypt('secret'),
                'role' => 'student',
                'university_code' => $university['code'],
            ]);
            $certificateCode = $university['code'] . '-JUNK-CERTIFICATE';
            Certificate::create([
                'certificate_code' => $certificateCode,
                'student_name' => $student->name,
                'recipient_name' => $student->name,
                'student_id' => $university['code'] . '-JUNK-1001',
                'student_email' => $student->email,
                'degree' => 'BSIT',
                'course_or_event' => 'BSIT',
                'university_code' => $university['code'],
                'issue_date' => '2026-06-01',
                'status' => 'Verified',
                'cert_hash' => str_repeat($university['code'] === 'UCU' ? 'a' : 'b', 64),
            ]);
            DB::table('certificates')
                ->where('certificate_code', $certificateCode)
                ->update(['email' => $student->email]);

            $students[] = [
                'admin' => $admin,
                'student' => $student,
                'code' => $university['code'],
                'certificate_code' => $certificateCode,
            ];
        }

        foreach ($students as $record) {
            $this->actingAs($superAdmin, 'sanctum')
                ->deleteJson('/api/admin/subadmins/' . $record['admin']->id)
                ->assertOk();
        }

        $junkResponse = $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/junk')
            ->assertOk()
            ->assertJsonCount(4, 'data');
        $this->assertEqualsCanonicalizing(
            ['student_account', 'student_account', 'subadmin_account', 'subadmin_account'],
            collect($junkResponse->json('data'))->pluck('record_type')->all(),
        );

        foreach ($students as $record) {
            $this->assertDatabaseMissing('users', ['id' => $record['student']->id]);
            $this->assertDatabaseMissing('certificates', [
                'certificate_code' => $record['certificate_code'],
            ]);
            $this->getJson('/api/certificates/' . $record['certificate_code'])
                ->assertStatus(410)
                ->assertJsonPath('status', 'removed');
            $junkItem = collect($junkResponse->json('data'))
                ->firstWhere('student_user_id', $record['student']->id);
            $this->assertSame(
                $record['certificate_code'],
                $junkItem['payload']['certificates'][0]['certificate_code'],
            );
            $this->actingAs($superAdmin, 'sanctum')
                ->deleteJson('/api/admin/junk/' . $junkItem['id'])
                ->assertOk()
                ->assertJsonPath('message', 'The item was permanently deleted from Junk.');

            $this->assertDatabaseMissing('users', ['id' => $record['student']->id]);
            $this->assertDatabaseMissing('certificates', [
                'certificate_code' => $record['certificate_code'],
            ]);
            $this->assertDatabaseHas('revoked_credentials', [
                'certificate_code' => $record['certificate_code'],
            ]);
        }

        $this->assertDatabaseHas('universities', ['code' => 'UCU']);
        $this->assertDatabaseHas('universities', ['code' => 'PSU']);
    }

    public function test_permanently_deleting_junk_item_does_not_delete_university_registration(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $universityAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-junk-bulk-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'Bulk Cleanup Student',
            'email' => 'ucu-junk-bulk-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        Certificate::create([
            'certificate_code' => 'UCU-JUNK-BULK-CERTIFICATE',
            'student_name' => $student->name,
            'recipient_name' => $student->name,
            'student_id' => 'UCU-JUNK-BULK-1001',
            'student_email' => $student->email,
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('c', 64),
        ]);

        $this->actingAs($universityAdmin, 'sanctum')
            ->deleteJson('/api/admin/students/' . $student->id)
            ->assertStatus(202);
        $requestId = DB::table('student_deletion_requests')
            ->where('student_user_id', $student->id)
            ->value('id');
        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/student-deletion-requests/' . $requestId, [
                'decision' => 'approved',
            ])
            ->assertOk();
        $junkItemId = DB::table('junk_items')
            ->where('student_user_id', $student->id)
            ->value('id');
        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/junk/' . $junkItemId)
            ->assertOk()
            ->assertJsonPath('message', 'The item was permanently deleted from Junk.');

        $this->assertDatabaseMissing('users', ['id' => $student->id]);
        $this->assertDatabaseHas('users', ['id' => $universityAdmin->id]);
        $this->assertDatabaseMissing('certificates', [
            'certificate_code' => 'UCU-JUNK-BULK-CERTIFICATE',
        ]);
        $this->assertDatabaseMissing('junk_items', ['id' => $junkItemId]);
        $this->assertDatabaseHas('universities', ['code' => 'UCU']);
    }

    public function test_superadmin_can_permanently_delete_an_unknown_junk_record(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $junkItemId = DB::table('junk_items')->insertGetId([
            'record_type' => 'unknown_record',
            'source' => 'legacy_cleanup',
            'payload' => json_encode([
                'certificates' => ['legacy certificate snapshot'],
            ], JSON_THROW_ON_ERROR),
            'deleted_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/junk')
            ->assertOk()
            ->assertJsonPath('data.0.id', $junkItemId)
            ->assertJsonPath('data.0.record_type', 'unknown_record');

        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/junk/' . $junkItemId)
            ->assertOk()
            ->assertJsonPath('message', 'The item was permanently deleted from Junk.');

        $this->assertDatabaseMissing('junk_items', ['id' => $junkItemId]);
    }

    public function test_student_access_lists_degrees_with_types_and_ordinals(): void
    {
        $admin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-degree-list@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        User::create([
            'name' => 'Multi-degree Student',
            'email' => 'multi-degree-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);

        foreach ([
            [
                'certificate_code' => 'CERT-DEGREE-LIST-BACHELOR',
                'degree' => 'Bachelor of Science in Information Technology',
                'degree_number' => 1,
                'issue_date' => '2024-06-01',
                'cert_hash' => str_repeat('a', 64),
            ],
            [
                'certificate_code' => 'CERT-DEGREE-LIST-MASTERAL',
                'degree' => 'Master of Science in Information Technology',
                'degree_number' => 2,
                'issue_date' => '2026-06-01',
                'cert_hash' => str_repeat('b', 64),
            ],
        ] as $credential) {
            Certificate::create(array_merge($credential, [
                'student_name' => 'Multi-degree Student',
                'recipient_name' => 'Multi-degree Student',
                'student_id' => 'UCU-MULTI-1001',
                'student_email' => 'multi-degree-student@example.edu',
                'course_or_event' => $credential['degree'],
                'university_code' => 'UCU',
                'status' => 'Verified',
            ]));
        }
        DB::table('certificates')
            ->whereIn('certificate_code', [
                'CERT-DEGREE-LIST-BACHELOR',
                'CERT-DEGREE-LIST-MASTERAL',
            ])
            ->update(['email' => 'multi-degree-student@example.edu']);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/admin/students')
            ->assertOk()
            ->assertJsonCount(2, 'data.0.credentials')
            ->assertJsonPath('data.0.credentials.0.degree_number', 1)
            ->assertJsonPath('data.0.credentials.0.degree_type', 'Undergraduate')
            ->assertJsonPath('data.0.credentials.1.degree_number', 2)
            ->assertJsonPath('data.0.credentials.1.degree_type', 'Masteral');
    }

    public function test_superadmin_can_freeze_university_access_scopes(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-freeze@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $ucuStudent = User::create([
            'name' => 'UCU Student',
            'email' => 'ucu-student-freeze@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        $psuStudent = User::create([
            'name' => 'PSU Student',
            'email' => 'psu-student-freeze@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/universities/UCU/access', [
                'scope' => 'students',
                'frozen' => true,
            ])->assertOk()
            ->assertJsonPath('scope', 'students')
            ->assertJsonPath('frozen', true);

        $this->assertTrue($ucuStudent->fresh()->isAccessFrozen());
        $this->assertFalse($psuStudent->fresh()->isAccessFrozen());
        $this->assertFalse($ucuAdmin->fresh()->isAccessFrozen());

        $this->patchJson('/api/admin/universities/UCU/access', [
            'scope' => 'admin',
            'frozen' => true,
        ])->assertOk();
        $this->assertTrue($ucuAdmin->fresh()->isAccessFrozen());

        $this->patchJson('/api/admin/universities/UCU/access', [
            'scope' => 'both',
            'frozen' => false,
        ])->assertOk();
        $this->assertFalse($ucuAdmin->fresh()->isAccessFrozen());
        $this->assertFalse($ucuStudent->fresh()->isAccessFrozen());
        $this->assertFalse($psuStudent->fresh()->isAccessFrozen());
    }

    public function test_subadmin_can_freeze_only_its_university_students(): void
    {
        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-student-control@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $ucuStudent = User::create([
            'name' => 'UCU Student',
            'email' => 'ucu-student-control@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        $psuStudent = User::create([
            'name' => 'PSU Student',
            'email' => 'psu-student-control@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);

        $this->actingAs($ucuAdmin, 'sanctum')
            ->getJson('/api/admin/students')
            ->assertOk()
            ->assertJsonPath('data.0.email', $ucuStudent->email);

        $this->patchJson('/api/admin/students/' . $ucuStudent->id . '/access', [
            'frozen' => true,
        ])->assertOk()->assertJsonPath('is_frozen', true);
        $this->assertTrue($ucuStudent->fresh()->isAccessFrozen());
        $this->assertFalse($ucuAdmin->fresh()->isAccessFrozen());

        $this->patchJson('/api/admin/students/' . $psuStudent->id . '/access', [
            'frozen' => true,
        ])->assertForbidden();

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/access', [
            'frozen' => true,
            ])->assertOk();
        $this->assertTrue($ucuStudent->fresh()->isAccessFrozen());
        $this->assertFalse($ucuAdmin->fresh()->isAccessFrozen());

        $this->patchJson('/api/admin/students/access', [
            'frozen' => false,
        ])->assertOk();
        $this->assertFalse($ucuStudent->fresh()->isAccessFrozen());
    }

    public function test_university_freeze_owner_can_restore_one_student_under_its_own_policy(): void
    {
        $psuAdmin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu2026admin@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $otherPsuAdmin = User::create([
            'name' => 'Other PSU Admin',
            'email' => 'other-psu-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $student = User::create([
            'name' => 'PSU Student',
            'email' => 'psu-student-individual-restore@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        $anotherStudent = User::create([
            'name' => 'Another PSU Student',
            'email' => 'psu-student-still-frozen@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);

        $this->actingAs($psuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/access', ['frozen' => true])
            ->assertOk();

        $this->actingAs($otherPsuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => false,
            ])->assertForbidden()
            ->assertJsonPath('freeze_owner_email', $psuAdmin->email);

        $this->actingAs($psuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => false,
            ])->assertOk()
            ->assertJsonPath('is_frozen', false);

        $this->assertFalse($student->fresh()->isAccessFrozen());
        $this->assertTrue($anotherStudent->fresh()->isAccessFrozen());
        $this->assertDatabaseHas('university_access_controls', [
            'university_code' => 'PSU',
            'students_frozen' => true,
            'updated_by' => $psuAdmin->id,
        ]);
    }

    public function test_only_the_freezing_administrator_can_unfreeze_individual_or_university_access(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-freeze-owner@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $otherUcuAdmin = User::create([
            'name' => 'Other UCU Admin',
            'email' => 'other-ucu-admin-freeze-owner@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'UCU Student',
            'email' => 'ucu-student-freeze-owner@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => true,
            ])->assertOk();

        DB::table('certificates')->insert([
            'certificate_code' => 'CERT-UCU-FROZEN-STUDENT',
            'recipient_name' => 'UCU Student',
            'student_name' => 'UCU Student',
            'student_id' => 'UCU-12345',
            'student_email' => $student->email,
            'course_or_event' => 'BSIT',
            'degree' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2024-06-01',
            'status' => 'valid',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/subadmins')
            ->assertOk()
            ->assertJsonPath('data.0.frozen_students.0.name', 'UCU Student')
            ->assertJsonPath('data.0.frozen_students.0.student_id', 'UCU-12345');

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/universities/UCU/access', [
                'scope' => 'students',
                'frozen' => false,
            ])->assertOk()
            ->assertJsonPath('protected_students.0.name', 'UCU Student')
            ->assertJsonPath('protected_students.0.student_id', 'UCU-12345');
        $this->assertTrue($student->fresh()->isAccessFrozen());

        $this->actingAs($otherUcuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => false,
            ])->assertForbidden();
        $this->assertTrue($student->fresh()->isAccessFrozen());

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => false,
            ])->assertOk();
        $this->assertFalse($student->fresh()->isAccessFrozen());

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/access', [
                'frozen' => true,
            ])->assertOk();
        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/universities/UCU/access', [
                'scope' => 'students',
                'frozen' => false,
            ])->assertForbidden()
            ->assertJsonPath('protected_students.0.name', 'UCU Student')
            ->assertJsonPath('protected_students.0.student_id', 'UCU-12345');
        $this->assertTrue($student->fresh()->isAccessFrozen());

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/access', [
                'frozen' => false,
            ])->assertOk();
        $this->assertFalse($student->fresh()->isAccessFrozen());
    }

    public function test_superadmin_can_list_and_freeze_students_but_cannot_unfreeze_an_account_frozen_by_a_subadmin(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-roster@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $studentFrozenBySubadmin = User::create([
            'name' => 'Protected Student',
            'email' => 'protected-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        $studentManagedBySuperadmin = User::create([
            'name' => 'Manageable Student',
            'email' => 'manageable-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        DB::table('certificates')->insert([
            'certificate_code' => 'CERT-SUPERADMIN-ROSTER',
            'recipient_name' => 'Protected Student',
            'student_name' => 'Protected Student',
            'student_id' => 'UCU-2026-001',
            'student_email' => $studentFrozenBySubadmin->email,
            'course_or_event' => 'BSIT',
            'degree' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'valid',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $studentFrozenBySubadmin->id . '/access', [
                'frozen' => true,
            ])->assertOk();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/universities/UCU/students')
            ->assertOk()
            ->assertJsonPath('data.0.email', 'manageable-student@example.edu')
            ->assertJsonPath('data.1.student_id', 'UCU-2026-001')
            ->assertJsonPath('data.1.degree', 'BSIT')
            ->assertJsonPath('data.1.batch_year', '2026')
            ->assertJsonPath('data.1.freeze_owner_email', $ucuAdmin->email)
            ->assertJsonPath('data.1.can_manage_access', false);

        $this->patchJson('/api/admin/students/' . $studentFrozenBySubadmin->id . '/access', [
            'frozen' => false,
        ])->assertForbidden()
            ->assertJsonPath('freeze_owner_email', $ucuAdmin->email);
        $this->assertTrue($studentFrozenBySubadmin->fresh()->isAccessFrozen());

        $this->patchJson('/api/admin/students/' . $studentManagedBySuperadmin->id . '/access', [
            'frozen' => true,
        ])->assertOk();
        $this->actingAs($ucuAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $studentManagedBySuperadmin->id . '/access', [
                'frozen' => false,
            ])->assertForbidden();
        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/students/' . $studentManagedBySuperadmin->id . '/access', [
                'frozen' => false,
            ])->assertOk();
        $this->assertFalse($studentManagedBySuperadmin->fresh()->isAccessFrozen());
    }

    public function test_superadmin_can_register_a_university_and_bind_its_subadmin(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/admin/subadmins', [
                'name' => 'University of Cebu Admin',
                'email' => 'new-ucu-admin@example.edu',
                'university_code' => 'UOCM',
                'university_name' => 'University of Cebu',
                'branch_campus' => 'Main Campus',
                'display_name' => 'UOCM',
            ])->assertCreated()
            ->assertJsonPath('data.university_code', 'UOCM');

        $this->getJson('/api/admin/universities')
            ->assertOk()
            ->assertJsonFragment([
                'code' => 'UOCM',
                'university_name' => 'University of Cebu',
                'branch_campus' => 'Main Campus',
                'display_name' => 'UOCM',
            ]);

        $this->patchJson('/api/admin/universities/UOCM/access', [
            'scope' => 'students',
            'frozen' => true,
        ])->assertOk();
    }

    public function test_changing_subadmin_google_email_clears_binding_and_revokes_old_tokens(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $subadmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'old-ucu-admin@example.edu',
            'password' => bcrypt('secret'),
            'google_id' => 'old-google-id',
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $subadmin->createToken('old-device');

        $this->actingAs($superAdmin, 'sanctum')
            ->putJson('/api/admin/subadmins/' . $subadmin->id, [
                'email' => 'replacement-ucu-admin@example.edu',
            ])->assertOk()
            ->assertJsonPath('data.email', 'replacement-ucu-admin@example.edu');

        $this->assertNull($subadmin->fresh()->google_id);
        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $subadmin->id,
        ]);
    }

    public function test_superadmin_overview_groups_total_and_verified_credentials_by_batch_and_university(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        foreach ([
            ['CERT-OVERVIEW-UCU-2026', 'UCU', '2026-06-01', 'Verified'],
            ['CERT-OVERVIEW-PSU-2026', 'PSU', '2026-06-02', 'Pending'],
            ['CERT-OVERVIEW-PSU-2025', 'PSU', '2025-06-03', 'Valid'],
        ] as [$code, $universityCode, $issueDate, $status]) {
            Certificate::create([
                'certificate_code' => $code,
                'recipient_name' => $code,
                'student_name' => $code,
                'student_id' => $code,
                'student_email' => strtolower($code) . '@example.edu',
                'email' => strtolower($code) . '@example.edu',
                'degree' => 'Bachelor of Science',
                'course_or_event' => 'Bachelor of Science',
                'university_code' => $universityCode,
                'issue_date' => $issueDate,
                'status' => $status,
                'cert_hash' => hash('sha256', $code),
            ]);
        }

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/admin/overview')
            ->assertOk()
            ->assertJsonPath('data.total_credentials', 3)
            ->assertJsonPath('data.verified_credentials', 2)
            ->assertJsonPath('data.credential_batches.0.batch_year', '2026')
            ->assertJsonPath('data.credential_batches.0.total_count', 2)
            ->assertJsonPath('data.credential_batches.0.verified_count', 1)
            ->assertJsonPath('data.credential_batches.0.universities.0.code', 'PSU')
            ->assertJsonPath('data.credential_batches.0.universities.0.total_count', 1)
            ->assertJsonPath('data.credential_batches.0.universities.1.code', 'UCU')
            ->assertJsonPath('data.credential_batches.1.batch_year', '2025')
            ->assertJsonPath('data.credential_batches.1.verified_count', 1);
    }

    public function test_frozen_account_can_sign_in_but_only_use_its_support_chat(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $student = User::create([
            'name' => 'Frozen Student',
            'email' => 'frozen-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
            'access_frozen' => true,
            'access_frozen_at' => now(),
            'access_frozen_by' => $superAdmin->id,
        ]);

        $this->postJson('/api/login', [
            'email' => $student->email,
            'password' => 'secret',
        ])->assertOk()
            ->assertJsonPath('access_frozen', true)
            ->assertJsonPath('freeze_contact.id', $superAdmin->id);

        $token = $student->createToken('frozen-test')->plainTextToken;
        $this->withToken($token)
            ->getJson('/api/certificates')
            ->assertStatus(423);
        $this->withToken($token)
            ->getJson('/api/user')
            ->assertOk()
            ->assertJsonPath('access_frozen', true)
            ->assertJsonPath('freeze_contact.id', $superAdmin->id);

        Http::fake([
            'https://www.googleapis.com/oauth2/v3/userinfo' => Http::response([
                'email' => $student->email,
                'email_verified' => true,
                'name' => $student->name,
                'sub' => 'frozen-student-google-id',
            ], 200),
        ]);
        $this->postJson('/api/auth/google', [
            'access_token' => 'fake-frozen-student-token',
        ])->assertOk()
            ->assertJsonPath('access_frozen', true)
            ->assertJsonPath('freeze_contact.id', $superAdmin->id);
    }

    public function test_frozen_user_can_message_only_the_freezer_and_keeps_history_after_unfreeze(): void
    {
        $admin = User::create([
            'name' => 'UCU Subadmin',
            'email' => 'ucu-subadmin-support@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'Frozen Student',
            'email' => 'frozen-student-chat@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
            'access_frozen' => true,
            'access_frozen_at' => now(),
            'access_frozen_by' => $admin->id,
        ]);
        $otherAdmin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-admin-support@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        ChatMessage::create([
            'user_id' => $admin->id,
            'recipient_user_id' => $student->id,
            'university_code' => 'UCU',
            'sender_email' => $admin->email,
            'sender_name' => $admin->name,
            'message' => 'Please contact me about your account access.',
        ]);
        $token = $student->createToken('frozen-support-chat')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $admin->id);

        $this->actingAs($student, 'sanctum')
            ->getJson('/api/chat/messages?with_user_id=' . $admin->id)
            ->assertOk()
            ->assertJsonPath('data.0.message', 'Please contact me about your account access.');

        $this->withToken($token)
            ->getJson('/api/chat/messages?with_user_id=' . $otherAdmin->id)
            ->assertForbidden();

        $this->withToken($token)
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $admin->id,
                'message' => 'I am contacting you to resolve the issue.',
            ])->assertCreated();

        $this->withToken($token)
            ->deleteJson('/api/chat/conversation/' . $admin->id)
            ->assertStatus(423);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonFragment(['id' => $student->id]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/admin/students/' . $student->id . '/access', [
                'frozen' => false,
            ])->assertOk();

        $this->assertDatabaseHas('chat_messages', [
            'user_id' => $admin->id,
            'message' => 'Please contact me about your account access.',
        ]);
        $this->assertDatabaseHas('chat_messages', [
            'user_id' => $student->id,
            'message' => 'I am contacting you to resolve the issue.',
        ]);

        $this->actingAs($student, 'sanctum')
            ->getJson('/api/chat/messages?with_user_id=' . $admin->id)
            ->assertOk()
            ->assertJsonCount(2, 'data');
    }

    public function test_frozen_account_without_university_code_can_reach_global_freezer(): void
    {
        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $student = User::create([
            'name' => 'Legacy Frozen Student',
            'email' => 'legacy-frozen-chat@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'access_frozen' => true,
            'access_frozen_at' => now(),
            'access_frozen_by' => $superAdmin->id,
        ]);
        ChatMessage::create([
            'user_id' => $superAdmin->id,
            'recipient_user_id' => $student->id,
            'university_code' => 'UCU',
            'sender_email' => $superAdmin->email,
            'sender_name' => $superAdmin->name,
            'message' => 'Please reply here to resolve your account restriction.',
        ]);
        $token = $student->createToken('legacy-frozen-support-chat')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $superAdmin->id);

        $this->withToken($token)
            ->getJson('/api/chat/messages?with_user_id=' . $superAdmin->id)
            ->assertOk()
            ->assertJsonPath('data.0.message', 'Please reply here to resolve your account restriction.');

        $this->withToken($token)
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $superAdmin->id,
                'message' => 'I can reach support from my account.',
            ])->assertCreated();
    }

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
            ->assertJsonPath('message', 'This Google account is not registered in CertiTrust yet. Please ask the system admin to create your account.');

        $this->assertDatabaseMissing('users', [
            'email' => 'demo.user@gmail.com',
        ]);
    }

    public function test_google_login_matches_registered_subadmin_email_case_insensitively_and_ignores_whitespace(): void
    {
        $subadmin = User::create([
            'name' => 'Registered Subadmin',
            'email' => '  Subadmin.Example@Example.edu ',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);

        Http::fake([
            'https://www.googleapis.com/oauth2/v3/userinfo' => Http::response([
                'email' => 'subadmin.example@example.edu',
                'email_verified' => true,
                'name' => 'Registered Subadmin',
                'sub' => 'registered-subadmin-123',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'access_token' => 'valid-access-token',
        ]);

        $response->assertOk()
            ->assertJsonPath('role', 'admin')
            ->assertJsonPath('university_code', 'UCU');
        $this->assertSame($subadmin->id, User::where('google_id', 'registered-subadmin-123')->value('id'));
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

        $this->withToken($login->json('token'))
            ->postJson('/api/auth/verify-student', [
                'email' => 'STUDENT@example.edu',
                'student_id' => 'wrong-id',
            ])
            ->assertNotFound()
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'The Student ID is incorrect. Please check it and try again.');
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
            ->assertJsonPath('message', 'Student ID "20260002" already belongs to Alex Student (Student ID 20260002). Confirm this as an additional degree to continue.');

        $this->postJson('/api/certificates/batch', [
            'certificates' => [$credential('20260004', 'e', 'alex-one@example.edu')],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Google email "alex-one@example.edu" is already linked to Alex Student. Each student must use a unique email.');

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
                array_merge(
                    $credential('20260007', 'j', 'file-owner@example.edu', $diplomaUrl),
                    ['diploma_file_name' => 'used-diploma.jpg'],
                ),
            ],
        ])->assertCreated();
        $this->getJson('/api/certificates/' . str_repeat('j', 64))
            ->assertOk()
            ->assertJsonPath('data.diploma_url', $diplomaUrl)
            ->assertJsonPath('data.diploma_file_name', 'used-diploma.jpg');
        $this->assertDatabaseHas('certificates', [
            'student_id' => '20260007',
            'diploma_file_name' => 'used-diploma.jpg',
        ]);
        DB::table('certificates')
            ->where('student_id', '20260007')
            ->update(['diploma_file_name' => null]);

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                array_merge(
                    $credential(
                        '20260008',
                        'k',
                        'file-reuse@example.edu',
                        'https://another-storage.example/other-folder/USED-DIPLOMA.jpg?download=1',
                    ),
                    ['diploma_file_name' => 'USED-DIPLOMA.jpg'],
                ),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Diploma image "used-diploma.jpg" already belongs to Alex Student (Student ID 20260007). Choose another image file.');

        $ucuAdmin = User::create([
            'name' => 'UCU Admin',
            'email' => 'ucu-admin-cross-campus@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $this->actingAs($ucuAdmin, 'sanctum')->postJson('/api/certificates/batch', [
            'certificates' => [[
                'student_id' => '20260008',
                'student_name' => 'Alex Student',
                'student_email' => 'cross-campus-email@example.edu',
                'degree' => 'BSIT',
                'university_code' => 'UCU',
                'issue_date' => '2026-09-30',
                'cert_hash' => str_repeat('n', 64),
                'diploma_url' => 'https://storage.example/diplomas/UCU-DIPLOMA.jpg',
                'diploma_file_name' => 'UCU-DIPLOMA.jpg',
            ]],
        ])->assertCreated();

        $this->actingAs($admin, 'sanctum')->postJson('/api/certificates/validate-batch', [
            'certificates' => [[
                'student_id' => '20260008',
                'student_name' => 'New PSU Student',
                'student_email' => 'new-psu-student@example.edu',
                'diploma_file_name' => 'fresh-diploma.jpg',
            ]],
        ])->assertOk()
            ->assertJsonPath('additional_degree_candidates', []);

        $this->postJson('/api/certificates/batch', [
            'certificates' => [[
                'student_id' => '20260008',
                'student_name' => 'New PSU Student',
                'student_email' => 'new-psu-student@example.edu',
                'degree' => 'BSIT',
                'university_code' => 'PSU',
                'issue_date' => '2026-09-30',
                'cert_hash' => str_repeat('p', 64),
            ]],
        ])->assertCreated()
            ->assertJsonPath('count', 1);

        $this->getJson('/api/certificates/CERTITRUST-MULTI:' . str_repeat('n', 64))
            ->assertOk()
            ->assertJsonPath('data.multi_degree', true)
            ->assertJsonPath('data.degree_count', 2)
            ->assertJsonPath('data.certificates.0.university_code', 'UCU')
            ->assertJsonPath('data.certificates.1.university_code', 'PSU');

        $this->postJson('/api/certificates/validate-batch', [
            'certificates' => [[
                'student_id' => '20260011',
                'student_name' => 'Alex Student',
                'student_email' => 'another-psu-student@example.edu',
                'diploma_file_name' => 'new-psu-diploma.jpg',
            ]],
        ])->assertOk()
            ->assertJsonPath('warnings.0', 'The name "Alex Student" is also used at UCU. Same names are allowed; you may continue.');

        $this->postJson('/api/certificates/validate-batch', [
            'certificates' => [[
                'student_id' => '20260011',
                'student_name' => 'Another Student',
                'student_email' => 'cross-campus-email@example.edu',
                'diploma_file_name' => 'fresh-diploma.jpg',
            ]],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Google email "cross-campus-email@example.edu" is already linked to Alex Student at UCU. Each student must use a unique email.');

        $this->actingAs($ucuAdmin, 'sanctum')->postJson('/api/certificates/validate-batch', [
            'certificates' => [[
                'student_id' => '20260008',
                'student_name' => 'Alex Student',
                'student_email' => 'cross-campus-email@example.edu',
                'degree' => 'BSIT',
                'diploma_file_name' => 'UCU-SECOND-DIPLOMA.jpg',
            ]],
        ])->assertOk()
            ->assertJsonPath('additional_degree_candidates.0.next_degree_number', 2)
            ->assertJsonPath('additional_degree_candidates.0.existing_degrees.0.degree', 'BSIT')
            ->assertJsonPath('additional_degree_candidates.0.existing_degrees.0.degree_number', 1);

        $confirmedAdditionalDegree = [[
            'student_id' => '20260008',
            'student_name' => 'Alex Student',
            'student_email' => 'cross-campus-email@example.edu',
            'degree' => 'BSCS',
            'degree_number' => 2,
            'additional_degree' => true,
            'university_code' => 'UCU',
            'issue_date' => '2026-09-30',
            'cert_hash' => str_repeat('r', 64),
            'diploma_file_name' => 'UCU-SECOND-DIPLOMA.jpg',
        ]];
        $this->actingAs($ucuAdmin, 'sanctum')->postJson('/api/certificates/validate-batch', [
            'certificates' => $confirmedAdditionalDegree,
        ])->assertOk()
            ->assertJsonPath('additional_degree_candidates', []);

        $this->actingAs($ucuAdmin, 'sanctum')->postJson('/api/certificates/batch', [
            'certificates' => $confirmedAdditionalDegree,
        ])->assertCreated();
        $this->assertDatabaseHas('certificates', [
            'student_id' => '20260008',
            'degree' => 'BSCS',
            'degree_number' => 2,
            'university_code' => 'UCU',
            'student_email' => 'cross-campus-email@example.edu',
        ]);

        $this->actingAs($admin, 'sanctum')->postJson('/api/certificates/batch', [
            'certificates' => [[
                'student_id' => '20260011',
                'student_name' => 'Another Student',
                'student_email' => 'cross-campus-email@example.edu',
                'degree' => 'BSIT',
                'university_code' => 'PSU',
                'issue_date' => '2026-09-30',
                'cert_hash' => str_repeat('q', 64),
            ]],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Google email "cross-campus-email@example.edu" is already linked to Alex Student at UCU. Each student must use a unique email.');

        $this->actingAs($admin, 'sanctum')->postJson('/api/certificates/validate-batch', [
            'certificates' => [[
                'student_id' => '20260012',
                'student_name' => 'Different PSU Student',
                'student_email' => 'different-psu-student@example.edu',
                'diploma_file_name' => 'USED-DIPLOMA.jpg',
            ]],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Diploma image "used-diploma.jpg" already belongs to Alex Student (Student ID 20260007). Choose another image file.');

        $this->actingAs($admin, 'sanctum')->postJson('/api/certificates/batch', [
            'certificates' => [[
                'student_id' => '20260013',
                'student_name' => 'Different PSU Student',
                'student_email' => 'different-psu-student@example.edu',
                'degree' => 'BSIT',
                'university_code' => 'PSU',
                'issue_date' => '2026-09-30',
                'cert_hash' => str_repeat('o', 64),
                'diploma_url' => 'https://storage.example/diplomas/UCU-DIPLOMA.jpg',
                'diploma_file_name' => 'UCU-DIPLOMA.jpg',
            ]],
        ])->assertCreated();

        $this->postJson('/api/certificates/check-diploma-file-names', [
            'file_names' => ['USED-DIPLOMA.jpg'],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Diploma image "used-diploma.jpg" already belongs to Alex Student (Student ID 20260007). Choose another image file.');

        $this->postJson('/api/certificates/batch', [
            'certificates' => [
                array_merge(
                    $credential('20260009', 'l', 'file-batch-one@example.edu'),
                    ['diploma_file_name' => 'new-diploma.png'],
                ),
                array_merge(
                    $credential('20260010', 'm', 'file-batch-two@example.edu'),
                    ['diploma_file_name' => 'NEW-DIPLOMA.PNG'],
                ),
            ],
        ])->assertStatus(422)
            ->assertJsonPath('message', 'Diploma image "new-diploma.png" is repeated in this batch and already belongs to Alex Student (Student ID 20260009).');
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
        $this->assertSame([$admin->id], $message->fresh()->deleted_by);

        $conversationResponse = $this->getJson('/api/chat/messages?student_id=' . $student->id);
        $conversationResponse->assertOk();
        $this->assertSame([], $conversationResponse->json('data'));

        $adminMessage = ChatMessage::create([
            'user_id' => $admin->id,
            'recipient_user_id' => $student->id,
            'university_code' => 'UCU',
            'sender_email' => $admin->email,
            'sender_name' => $admin->name,
            'message' => 'Admin message',
            'deleted_by' => [],
        ]);
        $studentMessage = ChatMessage::create([
            'user_id' => $student->id,
            'recipient_user_id' => $admin->id,
            'university_code' => 'UCU',
            'sender_email' => $student->email,
            'sender_name' => $student->name,
            'message' => 'Student message',
            'deleted_by' => [],
        ]);

        $this->getJson('/api/chat/messages?with_user_id=' . $student->id)
            ->assertOk()
            ->assertJsonFragment(['id' => $studentMessage->id]);
        $this->assertNotNull($studentMessage->fresh()->delivered_at);

        $this->deleteJson('/api/chat/conversation/' . $student->id . '?mode=everyone')
            ->assertOk()
            ->assertJsonPath('message', 'Conversation deleted for everyone.');
        $this->assertNotNull($adminMessage->fresh()->deleted_for_everyone_at);
        $this->assertNotNull($studentMessage->fresh()->deleted_for_everyone_at);
        $this->getJson('/api/chat/messages?student_id=' . $student->id)
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_chat_attachment_is_saved_to_public_supabase_storage(): void
    {
        config([
            'services.supabase.url' => 'https://chat-test.supabase.co',
            'services.supabase.service_role_key' => 'test-service-role-key',
            'services.supabase.chat_bucket' => 'chat-attachments',
        ]);
        Http::fake([
            'https://chat-test.supabase.co/storage/v1/bucket/chat-attachments' =>
                Http::response(['id' => 'chat-attachments', 'public' => true]),
            'https://chat-test.supabase.co/storage/v1/object/chat-attachments/*' =>
                Http::response(['Key' => 'chat/test.jpg'], 200),
        ]);
        $admin = User::create([
            'name' => 'UCU Attachment Admin',
            'email' => 'ucu-chat-attachment-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'UCU Attachment Student',
            'email' => 'ucu-chat-attachment-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-CHAT-ATTACHMENT',
            'recipient_name' => $student->name,
            'student_name' => $student->name,
            'student_id' => 'UCU-CHAT-ATTACHMENT',
            'student_email' => $student->email,
            'email' => $student->email,
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('d', 64),
        ]);

        $response = $this->actingAs($admin, 'sanctum')
            ->post('/api/chat/messages', [
                'recipient_user_id' => $student->id,
                'message' => 'See attached image.',
                'attachment' => UploadedFile::fake()->image('chat.jpg'),
            ], ['Accept' => 'application/json']);

        $response->assertCreated()
            ->assertJsonPath('data.attachment_type', 'image');
        $this->assertStringStartsWith(
            'https://chat-test.supabase.co/storage/v1/object/public/chat-attachments/chat/',
            $response->json('data.attachment_url'),
        );
        Http::assertSent(fn (HttpRequest $request) =>
            $request->method() === 'POST'
            && str_contains($request->url(), '/storage/v1/object/chat-attachments/chat/')
        );
    }

    public function test_chat_messages_and_unread_previews_are_shared_between_participants(): void
    {
        $admin = User::create([
            'name' => 'UCU Chat Admin',
            'email' => 'ucu-chat-sync-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'UCU Chat Student',
            'email' => 'ucu-chat-sync-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-CHAT-SYNC',
            'recipient_name' => $student->name,
            'student_name' => $student->name,
            'student_id' => 'UCU-CHAT-SYNC',
            'student_email' => $student->email,
            'email' => $student->email,
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('a', 64),
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $student->id,
                'message' => 'Please check your updated credential.',
            ])
            ->assertCreated()
            ->assertJsonPath('data.message', 'Please check your updated credential.');

        $this->actingAs($student, 'sanctum')
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonPath('data.0.last_message_preview', 'Please check your updated credential.')
            ->assertJsonPath('data.0.last_message_from_me', false)
            ->assertJsonPath('data.0.unread_count', 1);

        $this->getJson('/api/chat/messages?with_user_id=' . $admin->id)
            ->assertOk()
            ->assertJsonFragment(['message' => 'Please check your updated credential.']);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/chat/contacts')
            ->assertOk()
            ->assertJsonPath('data.0.last_message_preview', 'Please check your updated credential.')
            ->assertJsonPath('data.0.last_message_from_me', true)
            ->assertJsonPath('data.0.unread_count', 0);

        $this->actingAs($student, 'sanctum')
            ->postJson('/api/chat/messages', [
                'recipient_user_id' => $admin->id,
                'message' => 'Received, thank you.',
            ])
            ->assertCreated();

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/chat/messages?with_user_id=' . $student->id)
            ->assertOk()
            ->assertJsonFragment(['message' => 'Received, thank you.']);

        $this->deleteJson('/api/chat/conversation/' . $student->id . '?mode=me')
            ->assertOk()
            ->assertJsonPath('message', 'Conversation deleted for you.');
        $this->assertDatabaseHas('chat_messages', [
            'user_id' => $admin->id,
            'message' => 'Please check your updated credential.',
        ]);
        $this->assertSame(
            [$admin->id],
            ChatMessage::where('message', 'Please check your updated credential.')
                ->firstOrFail()
                ->deleted_by,
        );
        $this->getJson('/api/chat/messages?with_user_id=' . $student->id)
            ->assertOk()
            ->assertJsonPath('data', []);
        $this->actingAs($student, 'sanctum')
            ->getJson('/api/chat/messages?with_user_id=' . $admin->id)
            ->assertOk()
            ->assertJsonFragment(['message' => 'Please check your updated credential.'])
            ->assertJsonFragment(['message' => 'Received, thank you.']);
    }

    public function test_student_access_list_includes_credential_search_and_batch_year(): void
    {
        $admin = User::create([
            'name' => 'UCU Access Admin',
            'email' => 'ucu-access-credential-admin@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'UCU',
        ]);
        $student = User::create([
            'name' => 'Credential Search Student',
            'email' => 'credential-search-student@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'UCU',
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-STUDENT-ACCESS-2026',
            'recipient_name' => $student->name,
            'student_name' => $student->name,
            'student_id' => 'UCU-2026-SEARCH',
            'student_email' => $student->email,
            'email' => $student->email,
            'degree' => 'Bachelor of Science in Information Technology',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('b', 64),
        ]);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/admin/students')
            ->assertOk()
            ->assertJsonPath('data.0.student_id', 'UCU-2026-SEARCH')
            ->assertJsonPath('data.0.degree', 'Bachelor of Science in Information Technology')
            ->assertJsonPath('data.0.certificate_code', 'CERT-STUDENT-ACCESS-2026')
            ->assertJsonPath('data.0.batch_year', '2026')
            ->assertJsonPath(
                'data.0.credential_search',
                'UCU-2026-SEARCH Bachelor of Science in Information Technology BSIT CERT-STUDENT-ACCESS-2026',
            );
    }

    public function test_student_reports_and_super_admin_reply_and_approves_deletion_requests(): void
    {
        config([
            'services.supabase.url' => 'https://test-project.supabase.co',
            'services.supabase.service_role_key' => 'test-service-role-key',
            'services.supabase.diploma_bucket' => 'diplomas',
        ]);
        Http::fake(['*' => Http::response([], 404)]);

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
            'diploma_url' => 'https://test-project.supabase.co/storage/v1/object/public/diplomas/2026/diploma%20test.jpg',
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
        $this->getJson('/api/certificates/' . $certificate->certificate_code)
            ->assertStatus(410)
            ->assertJsonPath('status', 'removed');
        $this->assertDatabaseHas('certificate_deletion_requests', [
            'id' => $requestId,
            'student_id' => '20260077',
            'status' => 'approved',
        ]);
        $junkItem = DB::table('junk_items')
            ->where('record_type', 'credential_record')
            ->where('student_email', $student->email)
            ->first();
        $this->assertNotNull($junkItem);
        $this->assertDatabaseHas('junk_items', ['id' => $junkItem->id]);
        Http::assertNothingSent();
        $this->assertTrue(ChatMessage::where('user_id', $superAdmin->id)
            ->where('recipient_user_id', $admin->id)
            ->where('message', 'like', '%Deletion request%approved%')
            ->exists());
        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/junk/' . $junkItem->id)
            ->assertOk();
        Http::assertSent(fn (HttpRequest $request) => $request->method() === 'DELETE'
            && $request->url() === 'https://test-project.supabase.co/storage/v1/object/diplomas/2026/diploma%20test.jpg'
            && $request->hasHeader('apikey', 'test-service-role-key'));
    }

    public function test_permanent_junk_deletion_with_a_diploma_is_blocked_when_storage_is_unconfigured(): void
    {
        config([
            'services.supabase.url' => null,
            'services.supabase.service_role_key' => null,
            'services.supabase.diploma_bucket' => 'diplomas',
        ]);
        Http::fake();

        $superAdmin = User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $admin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-admin-storage@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);
        $certificate = \App\Models\Certificate::create([
            'certificate_code' => 'CERT-STORAGE-TEST',
            'recipient_name' => 'Test Student',
            'student_name' => 'Test Student',
            'student_id' => '20260078',
            'student_email' => 'storage-student@example.edu',
            'email' => 'storage-student@example.edu',
            'degree' => 'BSIT',
            'course_or_event' => 'BSIT',
            'university_code' => 'PSU',
            'issue_date' => '2026-09-30',
            'status' => 'Verified',
            'cert_hash' => str_repeat('d', 64),
            'diploma_url' => 'https://test-project.supabase.co/storage/v1/object/public/diplomas/diploma.jpg',
        ]);

        $this->actingAs($admin, 'sanctum');
        $deletionRequest = $this->postJson('/api/certificates/' . $certificate->id . '/deletion-request')
            ->assertCreated();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/admin/certificate-deletion-requests/' . $deletionRequest->json('data.id'), [
                'decision' => 'approved',
            ])->assertOk();

        $junkItemId = DB::table('junk_items')
            ->where('record_type', 'credential_record')
            ->value('id');
        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson('/api/admin/junk/' . $junkItemId)
            ->assertServiceUnavailable()
            ->assertJsonPath('message', 'Supabase Storage is not configured on the backend. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');

        $this->assertDatabaseMissing('certificates', ['id' => $certificate->id]);
        $this->assertDatabaseHas('junk_items', ['id' => $junkItemId]);
        $this->assertDatabaseHas('certificate_deletion_requests', [
            'id' => $deletionRequest->json('data.id'),
            'status' => 'approved',
        ]);
        Http::assertNothingSent();
    }

    public function test_school_admin_diploma_upload_creates_the_bucket_and_uses_a_unique_object_path(): void
    {
        $serviceRoleKey = 'sb_secret_test-service-role-key';
        $fileBytes = str_pad(
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nmAAAAABJRU5ErkJggg=='),
            2048,
            "\0",
        );
        config([
            'services.supabase.url' => 'https://test-project.supabase.co',
            'services.supabase.service_role_key' => $serviceRoleKey,
            'services.supabase.diploma_bucket' => 'diplomas',
        ]);
        Http::fake([
            'https://test-project.supabase.co/storage/v1/bucket/diplomas' => Http::response([
                'message' => 'Bucket not found',
            ], 400),
            'https://test-project.supabase.co/storage/v1/bucket' => Http::response([], 200),
            'https://test-project.supabase.co/storage/v1/object/diplomas/*' => Http::response([], 200),
        ]);

        $admin = User::create([
            'name' => 'PSU Admin',
            'email' => 'psu-admin-upload@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->post('/api/certificates/diploma', [
                'diploma_file' => UploadedFile::fake()->createWithContent(
                    'reused-name.png',
                    $fileBytes,
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('data.diploma_file_name', 'reused-name.png')
            ->assertJsonPath(
                'data.diploma_url',
                fn (string $url) => preg_match(
                    '#^https://test-project\.supabase\.co/storage/v1/object/public/diplomas/[0-9a-f-]+\.png$#',
                    $url,
                ) === 1,
            );

        Http::assertSent(fn (HttpRequest $request) => $request->method() === 'POST'
            && $request->url() === 'https://test-project.supabase.co/storage/v1/bucket'
            && $request->data()['public'] === true);
        Http::assertSent(fn (HttpRequest $request) => $request->method() === 'POST'
            && preg_match('#/storage/v1/object/diplomas/[0-9a-f-]+\.png$#', $request->url()) === 1
            && $request->hasHeader('apikey', $serviceRoleKey)
            && !$request->hasHeader('Authorization')
            && $request->body() === $fileBytes);
    }
}
