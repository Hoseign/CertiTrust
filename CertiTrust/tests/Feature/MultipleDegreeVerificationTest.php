<?php

namespace Tests\Feature;

use App\Models\Certificate;
use App\Models\University;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MultipleDegreeVerificationTest extends TestCase
{
    use RefreshDatabase;

    public function test_multiple_degree_code_returns_all_degrees_for_one_student_and_school(): void
    {
        $firstDegree = Certificate::create([
            'certificate_code' => 'CERT-FIRST-DEGREE',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'UCU-1001',
            'student_email' => 'alex@example.edu',
            'email' => 'alex@example.edu',
            'degree' => 'Bachelor of Science in Information Technology',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2024-06-01',
            'degree_number' => 1,
            'status' => 'Verified',
            'cert_hash' => str_repeat('a', 64),
            'diploma_url' => 'https://example.edu/diplomas/bsit.jpg',
        ]);

        Certificate::create([
            'certificate_code' => 'CERT-SECOND-DEGREE',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'UCU-1001',
            'student_email' => 'alex@example.edu',
            'email' => 'alex@example.edu',
            'degree' => 'Bachelor of Science in Accountancy',
            'course_or_event' => 'BSA',
            'university_code' => 'UCU',
            'issue_date' => '2026-06-01',
            'degree_number' => 2,
            'status' => 'Verified',
            'cert_hash' => str_repeat('b', 64),
            'diploma_url' => 'https://example.edu/diplomas/bsa.jpg',
        ]);

        Certificate::create([
            'certificate_code' => 'CERT-THIRD-DEGREE',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'UCU-1001',
            'student_email' => 'alex@example.edu',
            'email' => 'alex@example.edu',
            'degree' => 'Master of Information Technology',
            'course_or_event' => 'MIT',
            'university_code' => 'UCU',
            'issue_date' => '2028-06-01',
            'degree_number' => 3,
            'status' => 'Verified',
            'cert_hash' => str_repeat('d', 64),
            'diploma_url' => 'https://example.edu/diplomas/mit.jpg',
        ]);

        Certificate::create([
            'certificate_code' => 'CERT-OTHER-SCHOOL',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'UCU-1001',
            'student_email' => 'alex@example.edu',
            'email' => 'alex@example.edu',
            'degree' => 'Other university credential',
            'course_or_event' => 'Other',
            'university_code' => 'PSU',
            'issue_date' => '2025-06-01',
            'degree_number' => 1,
            'status' => 'Verified',
            'cert_hash' => str_repeat('c', 64),
            'diploma_url' => 'https://example.edu/diplomas/other.jpg',
        ]);

        $this->getJson('/api/certificates/CERTITRUST-MULTI:' . $firstDegree->cert_hash)
            ->assertOk()
            ->assertJsonPath('data.multi_degree', true)
            ->assertJsonPath('data.degree_count', 4)
            ->assertJsonPath('data.status', 'verified')
            ->assertJsonPath('data.certificates.0.degree_number', 1)
            ->assertJsonPath('data.certificates.0.university_name', 'Urdaneta City University')
            ->assertJsonPath('data.certificates.1.degree_number', 1)
            ->assertJsonPath('data.certificates.1.university_code', 'PSU')
            ->assertJsonPath('data.certificates.1.university_name', 'Pangasinan State University')
            ->assertJsonPath('data.certificates.2.degree_number', 2)
            ->assertJsonPath('data.certificates.3.degree_number', 3)
            ->assertJsonPath('data.certificates.0.diploma_url', 'https://example.edu/diplomas/bsit.jpg')
            ->assertJsonPath('data.certificates.1.diploma_url', 'https://example.edu/diplomas/other.jpg')
            ->assertJsonPath('data.certificates.2.diploma_url', 'https://example.edu/diplomas/bsa.jpg')
            ->assertJsonPath('data.certificates.3.diploma_url', 'https://example.edu/diplomas/mit.jpg');
    }

    public function test_public_verification_includes_registered_university_and_branch_name(): void
    {
        University::create([
            'code' => 'UOCM',
            'university_name' => 'University of Cebu',
            'branch_campus' => 'Main Campus',
            'display_name' => 'UOCM',
        ]);
        $certificate = Certificate::create([
            'certificate_code' => 'CERT-UOC-MAIN',
            'recipient_name' => 'Jordan Student',
            'student_name' => 'Jordan Student',
            'student_id' => 'UOC-2026-100',
            'student_email' => 'jordan@example.edu',
            'degree' => 'Bachelor of Science in Information Technology',
            'course_or_event' => 'BSIT',
            'university_code' => 'UOCM',
            'issue_date' => '2026-06-01',
            'status' => 'Verified',
            'cert_hash' => str_repeat('9', 64),
        ]);

        $this->getJson('/api/certificates/' . $certificate->certificate_code)
            ->assertOk()
            ->assertJsonPath('data.university_name', 'University of Cebu')
            ->assertJsonPath('data.branch_campus', 'Main Campus')
            ->assertJsonPath('data.display_name', 'UOCM');
    }

    public function test_replacement_student_email_can_access_credentials_by_student_id(): void
    {
        $student = User::create([
            'name' => 'Alex Student',
            'email' => 'new-alex@example.edu',
            'password' => bcrypt('secret'),
            'role' => 'student',
            'university_code' => 'PSU',
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-OLD-EMAIL',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'SHARED-STUDENT-1001',
            'student_email' => 'old-alex@example.edu',
            'degree' => 'Bachelor of Science in Information Technology',
            'course_or_event' => 'BSIT',
            'university_code' => 'UCU',
            'issue_date' => '2024-06-01',
            'degree_number' => 1,
            'status' => 'Verified',
            'cert_hash' => str_repeat('e', 64),
        ]);
        Certificate::create([
            'certificate_code' => 'CERT-NEW-EMAIL',
            'recipient_name' => 'Alex Student',
            'student_name' => 'Alex Student',
            'student_id' => 'SHARED-STUDENT-1001',
            'student_email' => 'new-alex@example.edu',
            'degree' => 'Bachelor of Science in Accountancy',
            'course_or_event' => 'BSA',
            'university_code' => 'PSU',
            'issue_date' => '2026-06-01',
            'degree_number' => 1,
            'status' => 'Verified',
            'cert_hash' => str_repeat('f', 64),
        ]);

        $this->actingAs($student, 'sanctum')
            ->getJson('/api/certificates')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonFragment(['certificate_code' => 'CERT-OLD-EMAIL'])
            ->assertJsonFragment(['certificate_code' => 'CERT-NEW-EMAIL']);
    }
}
