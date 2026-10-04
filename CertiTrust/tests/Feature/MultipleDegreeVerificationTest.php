<?php

namespace Tests\Feature;

use App\Models\Certificate;
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
            ->assertJsonPath('data.degree_count', 3)
            ->assertJsonPath('data.status', 'verified')
            ->assertJsonPath('data.certificates.0.degree_number', 1)
            ->assertJsonPath('data.certificates.1.degree_number', 2)
            ->assertJsonPath('data.certificates.2.degree_number', 3)
            ->assertJsonPath('data.certificates.0.diploma_url', 'https://example.edu/diplomas/bsit.jpg')
            ->assertJsonPath('data.certificates.1.diploma_url', 'https://example.edu/diplomas/bsa.jpg')
            ->assertJsonPath('data.certificates.2.diploma_url', 'https://example.edu/diplomas/mit.jpg');
    }
}
