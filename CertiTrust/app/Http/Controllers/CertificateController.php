<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use App\Models\User;
use App\Models\Certificate;
use App\Models\CertificateVerification;
use App\Models\University;
use App\Models\AdminActionLog;
use App\Services\SupabaseDiplomaStorage;
use App\Services\BlockchainRegistryService;

class CertificateController extends Controller
{
    public function index(Request $request)
    {
        $query = Certificate::query()->latest('issue_date');
        $user = $request->user();
        if ($user?->role === 'student') {
            $email = strtolower(trim((string) $user->email));
            $studentIds = Certificate::query()
                ->where(function ($studentCertificates) use ($email) {
                    $studentCertificates->whereRaw(
                        'LOWER(TRIM(student_email)) = ?',
                        [$email],
                    )->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
                })
                ->pluck('student_id')
                ->map(fn ($studentId) => strtolower(trim((string) $studentId)))
                ->filter()
                ->unique()
                ->values()
                ->all();
            $query->where(function ($studentCertificates) use ($email, $studentIds) {
                $studentCertificates->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
                if ($studentIds !== []) {
                    $studentCertificates->orWhereIn(
                        DB::raw('LOWER(TRIM(student_id))'),
                        $studentIds,
                    );
                }
            });
        } elseif ($user?->university_code) {
            $query->where('university_code', $user->university_code);
        }

        $limit = $request->integer('limit');
        if ($limit > 0) {
            $query->reorder()
                ->latest('created_at')
                ->limit(min($limit, 20));
        }

        return response()->json(['data' => $query->get()]);
    }

    public function show(string $code, BlockchainRegistryService $blockchain)
    {
        $normalizedCode = trim($code);
        $multipleDegreePrefix = 'CERTITRUST-MULTI:';
        $isMultipleDegreeCode = str_starts_with(
            strtoupper($normalizedCode),
            $multipleDegreePrefix,
        );
        if ($isMultipleDegreeCode) {
            $normalizedCode = substr($normalizedCode, strlen($multipleDegreePrefix));
        }

        $certificate = Certificate::where('certificate_code', $normalizedCode)
            ->orWhereRaw('LOWER(cert_hash) = ?', [strtolower($normalizedCode)])
            ->first();

        if ($certificate && $isMultipleDegreeCode) {
            $degreesQuery = Certificate::query();
            if (filled($certificate->student_id)) {
                $degreesQuery->whereRaw(
                    'LOWER(TRIM(student_id)) = ?',
                    [strtolower(trim((string) $certificate->student_id))],
                );
            } elseif (filled($certificate->student_email)) {
                $degreesQuery->whereRaw(
                    'LOWER(TRIM(student_email)) = ?',
                    [strtolower(trim((string) $certificate->student_email))],
                );
            } else {
                return response()->json([
                    'message' => 'This credential cannot be grouped with other degrees.',
                ], 404);
            }

            $degrees = $degreesQuery
                ->orderBy('degree_number')
                ->orderBy('issue_date')
                ->orderBy('id')
                ->get();

            if ($degrees->count() < 2) {
                return response()->json([
                    'message' => 'This credential does not have multiple degrees to verify.',
                ], 404);
            }

            $allVerified = $degrees->every(
                fn (Certificate $degree) => in_array(
                    strtolower(trim((string) $degree->status)),
                    ['verified', 'valid'],
                    true,
                ),
            );
            $degrees = $degrees->map(function (Certificate $degree) use ($blockchain) {
                $data = $this->publicCertificateData($degree);
                $data['blockchain_verification'] = $blockchain->verifyCertificate(
                    (string) $degree->cert_hash,
                );
                return $data;
            });

            if ($allVerified) {
                CertificateVerification::create([
                    'certificate_id' => $certificate->id,
                ]);
            }

            return response()->json([
                'data' => [
                    'multi_degree' => true,
                    'degree_count' => $degrees->count(),
                    'student_name' => $certificate->student_name ?: $certificate->recipient_name,
                    'student_id' => $certificate->student_id,
                    'university_code' => $certificate->university_code,
                    'status' => $allVerified ? 'verified' : 'invalid',
                    'certificates' => $degrees,
                ],
            ]);
        }

        if (!$certificate) {
            $revoked = Schema::hasTable('revoked_credentials')
                && DB::table('revoked_credentials')
                    ->where(function ($query) use ($normalizedCode) {
                        $query->whereRaw('LOWER(certificate_code) = ?', [strtolower($normalizedCode)])
                            ->orWhereRaw('LOWER(cert_hash) = ?', [strtolower($normalizedCode)]);
                    })
                    ->exists();
            if ($revoked) {
                return response()->json([
                    'status' => 'removed',
                    'message' => 'This credential was removed from the database and is no longer valid.',
                ], 410);
            }

            return response()->json(['message' => 'Certificate not found.'], 404);
        }

        $status = strtolower(trim((string) $certificate->status));
        if (in_array($status, ['verified', 'valid'], true)) {
            CertificateVerification::create([
                'certificate_id' => $certificate->id,
            ]);
        }

        $data = $this->publicCertificateData($certificate);
        $data['blockchain_verification'] = $blockchain->verifyCertificate(
            (string) $certificate->cert_hash,
        );

        return response()->json(['data' => $data]);
    }

    public function revoke(Request $request, Certificate $certificate)
    {
        $actor = $request->user();
        if (
            $actor?->role !== 'admin'
            || strtolower(trim((string) $actor->email)) !== 'certitrust256@gmail.com'
        ) {
            return response()->json([
                'message' => 'Only the Super Admin can revoke a credential record.',
            ], 403);
        }
        if (!Schema::hasTable('revoked_credentials') || !Schema::hasTable('junk_items')) {
            return response()->json([
                'message' => 'Credential removal tracking and the recycle bin are unavailable. Apply pending database migrations before removing credentials.',
            ], 503);
        }

        $certificateCode = $certificate->certificate_code;
        $targetEmail = $certificate->student_email ?: $certificate->email;
        $universityCode = $certificate->university_code;
        $certificateId = $certificate->id;
        $certificateHash = $certificate->cert_hash;

        DB::transaction(function () use (
            $certificate,
            $actor,
            $certificateCode,
            $certificateHash,
            $targetEmail,
            $universityCode,
            $certificateId,
        ): void {
            DB::table('revoked_credentials')->insert([
                'certificate_code' => $certificateCode,
                'cert_hash' => $certificateHash,
                'university_code' => $universityCode,
                'revoked_by_email' => $actor->email,
                'revoked_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('junk_items')->insert([
                'record_type' => 'credential_record',
                'university_code' => $universityCode,
                'student_name' => $certificate->student_name ?: $certificate->recipient_name,
                'student_email' => $targetEmail,
                'student_id' => $certificate->student_id,
                'source' => 'credential_revoked',
                'deleted_by_email' => $actor->email,
                'payload' => json_encode([
                    'certificates' => [$certificate->toArray()],
                ], JSON_THROW_ON_ERROR),
                'deleted_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $certificate->delete();
            if (Schema::hasTable('admin_action_logs')) {
                AdminActionLog::create([
                    'actor_email' => $actor->email,
                    'action' => 'revoked_certificate_record',
                    'target_email' => $targetEmail,
                    'university_code' => $universityCode,
                    'details' => [
                        'certificate_id' => $certificateId,
                        'certificate_code' => $certificateCode,
                    ],
                ]);
            }
        });

        return response()->json([
            'message' => 'The database credential was revoked and moved to Junk. Its QR code reports removed; immutable blockchain transactions remain on-chain.',
            'data' => [
                'certificate_id' => $certificateId,
                'certificate_code' => $certificateCode,
                'university_code' => $universityCode,
            ],
        ]);
    }

    public function recentVerifications(Request $request)
    {
        $user = $request->user();
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        if ($user?->role !== 'admin' || (!$isSuperAdmin && !$user->university_code)) {
            return response()->json([
                'message' => 'Only authorized administrators can view recent verifications.',
            ], 403);
        }

        $query = CertificateVerification::query()
            ->with('certificate')
            ->whereHas('certificate', function ($certificates) use ($user, $isSuperAdmin) {
                if (!$isSuperAdmin) {
                    $certificates->where('university_code', $user->university_code);
                }
            })
            ->latest('created_at');

        $limit = $request->integer('limit', 5);
        $verifications = $query
            ->limit(max(1, min($limit, 20)))
            ->get()
            ->map(function (CertificateVerification $verification) {
                $certificate = $verification->certificate;
                return array_merge(
                    $certificate->toArray(),
                    $this->universityDetails($certificate->university_code),
                    ['verified_at' => $verification->created_at],
                );
            });

        return response()->json(['data' => $verifications]);
    }

    private function universityDetails(?string $universityCode): array
    {
        $university = $universityCode ? University::find($universityCode) : null;

        return [
            'university_name' => $university?->university_name
                ?: $universityCode
                ?: 'Verified academic institution',
            'branch_campus' => $university?->branch_campus,
            'display_name' => $university?->display_name ?: $universityCode,
        ];
    }

    private function publicCertificateData(Certificate $certificate): array
    {
        return array_merge(
            $certificate->only([
                'id',
                'certificate_code',
                'recipient_name',
                'student_name',
                'student_id',
                'degree',
                'degree_number',
                'course_or_event',
                'university_code',
                'issue_date',
                'status',
                'cert_hash',
                'diploma_url',
                'diploma_file_name',
                'blockchain_status',
                'blockchain_tx_hash',
                'blockchain_network',
                'created_at',
            ]),
            $this->universityDetails($certificate->university_code),
        );
    }

    public function uploadDiploma(Request $request, SupabaseDiplomaStorage $storage)
    {
        $user = $request->user();
        $validated = $request->validate([
            'diploma_file' => ['required', 'file', 'mimes:pdf,png,jpg,jpeg', 'min:1', 'max:20480'],
            'university_code' => ['nullable', 'string', 'exists:universities,code'],
        ]);
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        $universityCode = $isSuperAdmin
            ? ($validated['university_code'] ?? null)
            : $user?->university_code;
        if ($user?->role !== 'admin' || !$universityCode) {
            return response()->json(['message' => 'A registered administrator and university are required to upload diploma files.'], 403);
        }

        $result = $storage->upload($validated['diploma_file']);
        if (!isset($result['url'])) {
            return response()->json(['message' => $result['message']], $result['status']);
        }

        return response()->json([
            'data' => [
                'diploma_url' => $result['url'],
                'diploma_file_name' => $validated['diploma_file']->getClientOriginalName(),
            ],
        ], 201);
    }

    public function store(Request $request, BlockchainRegistryService $blockchain)
    {
        $validated = $request->validate([
            'student_id' => ['required', 'string', 'max:255'],
            'student_name' => ['required', 'string', 'max:255'],
            'student_email' => ['required', 'email'],
            'degree' => ['required', 'string', 'max:255'],
            'issue_date' => ['required', 'date'],
            'cert_hash' => ['required', 'string', 'unique:certificates,cert_hash'],
            'diploma_url' => ['nullable', 'url'],
            'diploma_file_name' => ['nullable', 'string', 'max:255'],
            'university_code' => ['nullable', 'string', 'exists:universities,code'],
        ]);

        $user = $request->user();
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        $universityCode = $isSuperAdmin
            ? ($validated['university_code'] ?? null)
            : $user?->university_code;
        if (
            $user?->role !== 'admin'
            || !$universityCode
            || (!$isSuperAdmin && ($validated['university_code'] ?? $universityCode) !== $universityCode)
        ) {
            return response()->json(['message' => 'This admin is not authorized to issue for that school.'], 403);
        }
        $studentId = strtolower(trim($validated['student_id']));
        $existingStudent = $this->findStudentByIds([$studentId], $universityCode);
        if ($existingStudent) {
            return response()->json([
                'message' => 'Student ID "' . trim($validated['student_id']) . '" already belongs to ' . $this->studentOwnerLabel($existingStudent) . '. Enter a unique Student ID.',
            ], 422);
        }
        $studentEmail = strtolower(trim($validated['student_email']));
        $emailOwner = $this->findStudentByEmail($studentEmail);
        if ($emailOwner) {
            return response()->json([
                'message' => $this->emailConflictMessage($studentEmail, $emailOwner, $universityCode),
            ], 422);
        }
        $diplomaUrl = $validated['diploma_url'] ?? null;
        $diplomaFileName = $this->normalizedDiplomaFileName(
            ($validated['diploma_file_name'] ?? '') ?: $diplomaUrl
        );
        if ($diplomaFileName !== '') {
            $existingDiplomas = Certificate::where('university_code', $universityCode)
                ->where(function ($query) {
                $query->whereNotNull('diploma_file_name')
                    ->orWhereNotNull('diploma_url');
                })
                ->get(['student_id', 'student_name', 'recipient_name', 'diploma_url', 'diploma_file_name']);
            $existingOwner = $existingDiplomas->first(
                fn (Certificate $certificate) => $this->normalizedDiplomaFileName($certificate->diploma_file_name ?: $certificate->diploma_url) === $diplomaFileName
            );
            if ($existingOwner) {
                return response()->json([
                    'message' => 'Diploma image "' . $diplomaFileName . '" already belongs to ' . $this->studentOwnerLabel($existingOwner) . '. Choose another image file.',
                ], 422);
            }
        }

        $validated['student_id'] = trim($validated['student_id']);
        $validated['student_email'] = $studentEmail;
        $validated['certificate_code'] = 'CERT-' . strtoupper(Str::random(10));
        $validated['email'] = $studentEmail;
        $validated['diploma_file_name'] = $diplomaFileName ?: null;
        $validated['recipient_name'] = $validated['student_name'];
        $validated['course_or_event'] = $validated['degree'];
        $validated['university_code'] = $universityCode;
        $validated['status'] = 'Verified';

        $certificate = Certificate::create($validated);
        $blockchainResult = $this->anchorCertificate($blockchain, $certificate);

        return response()->json([
            'data' => $certificate->fresh(),
            'blockchain' => $blockchainResult,
        ], 201);
    }

    public function storeBatch(Request $request, BlockchainRegistryService $blockchain)
    {
        $validated = $request->validate([
            'certificates' => ['required', 'array', 'min:1'],
            'university_code' => ['nullable', 'string', 'exists:universities,code'],
            'certificates.*.student_id' => ['required', 'string', 'max:255'],
            'certificates.*.student_name' => ['required', 'string', 'max:255'],
            'certificates.*.student_email' => ['required', 'email'],
            'certificates.*.degree' => ['required', 'string', 'max:255'],
            'certificates.*.degree_number' => ['nullable', 'integer', 'min:1', 'max:65535'],
            'certificates.*.additional_degree' => ['nullable', 'boolean'],
            'certificates.*.issue_date' => ['required', 'date'],
            'certificates.*.cert_hash' => ['required', 'string'],
            'certificates.*.diploma_url' => ['nullable', 'url'],
            'certificates.*.diploma_file_name' => ['nullable', 'string', 'max:255'],
            'certificates.*.university_code' => ['nullable', 'string', 'exists:universities,code'],
        ]);

        $user = $request->user();
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        $universityCode = $isSuperAdmin
            ? ($validated['university_code'] ?? null)
            : $user?->university_code;
        if ($user?->role !== 'admin' || !$universityCode) {
            return response()->json(['message' => 'A registered administrator and university are required to issue credentials.'], 403);
        }
        $certificates = collect($validated['certificates']);
        if ($certificates->contains(fn (array $certificate) => ($certificate['university_code'] ?? $universityCode) !== $universityCode)) {
            return response()->json(['message' => 'This admin is not authorized to issue for that school.'], 403);
        }
        $batchStudentOwners = [];
        foreach ($certificates as $certificate) {
            $studentId = strtolower(trim($certificate['student_id']));
            $owner = ($certificate['student_name'] ?: 'Student') . ' (Student ID ' . trim($certificate['student_id']) . ')';
            if (isset($batchStudentOwners[$studentId])) {
                return response()->json([
                    'message' => 'Student ID "' . trim($certificate['student_id']) . '" is repeated in this batch and already belongs to ' . $batchStudentOwners[$studentId] . '.',
                ], 422);
            }
            $batchStudentOwners[$studentId] = $owner;
        }
        foreach ($certificates as $certificate) {
            $existingStudent = $this->findStudentByIds([
                strtolower(trim($certificate['student_id'])),
            ], $universityCode);
            $isAdditionalDegree = (bool) ($certificate['additional_degree'] ?? false);
            if (!$existingStudent && $isAdditionalDegree) {
                return response()->json([
                    'message' => 'An additional degree can only be issued for an existing student.',
                ], 422);
            }
            if ($existingStudent) {
                if (!$isAdditionalDegree) {
                    return response()->json([
                        'message' => 'Student ID "' . $existingStudent->student_id . '" already belongs to ' . $this->studentOwnerLabel($existingStudent) . '. Confirm this as an additional degree to continue.',
                    ], 422);
                }
                $nextDegreeNumber = $this->nextDegreeNumber($universityCode, $certificate['student_id']);
                if ((int) ($certificate['degree_number'] ?? 0) !== $nextDegreeNumber) {
                    return response()->json([
                        'message' => 'This student is ready for degree ' . $nextDegreeNumber . '. Refresh issuance validation and confirm the suggested degree number.',
                    ], 422);
                }
            } elseif ((int) ($certificate['degree_number'] ?? 1) !== 1) {
                return response()->json([
                    'message' => 'A student’s first credential must use degree number 1.',
                ], 422);
            }
        }
        $studentEmails = $certificates->map(fn (array $certificate) => strtolower(trim($certificate['student_email'])));
        if ($studentEmails->duplicates()->isNotEmpty()) {
            return response()->json([
                'message' => 'A Google email is repeated in this batch. Each student must use a unique email.',
            ], 422);
        }
        foreach ($studentEmails as $studentEmail) {
            $emailOwner = $this->findStudentByEmail($studentEmail);
            if ($emailOwner) {
                $emailCertificate = DB::table('certificates')
                    ->whereRaw('LOWER(TRIM(student_email)) = ?', [$studentEmail])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$studentEmail])
                    ->first(['student_id', 'university_code']);
                $batchCredential = $certificates->first(
                    fn (array $certificate) => strtolower(trim($certificate['student_email'])) === $studentEmail
                );
                if (
                    $batchCredential
                    && $emailCertificate
                    && strtolower(trim((string) $emailCertificate->student_id))
                        === strtolower(trim($batchCredential['student_id']))
                    && $emailCertificate->university_code === $universityCode
                ) {
                    continue;
                }
                return response()->json([
                    'message' => $this->emailConflictMessage($studentEmail, $emailOwner, $universityCode),
                ], 422);
            }
        }

        $batchFileOwners = [];
        foreach ($certificates as $certificate) {
            $fileName = $this->normalizedDiplomaFileName(
                ($certificate['diploma_file_name'] ?? '') ?: ($certificate['diploma_url'] ?? null)
            );
            if ($fileName === '') {
                continue;
            }
            $owner = ($certificate['student_name'] ?: 'Student') . ' (Student ID ' . trim($certificate['student_id']) . ')';
            if (isset($batchFileOwners[$fileName])) {
                return response()->json([
                    'message' => 'Diploma image "' . $fileName . '" is repeated in this batch and already belongs to ' . $batchFileOwners[$fileName] . '.',
                ], 422);
            }
            $batchFileOwners[$fileName] = $owner;
        }

        if ($batchFileOwners !== []) {
            $existingFileOwners = [];
            $existingDiplomas = Certificate::where('university_code', $universityCode)
                ->where(function ($query) {
                $query->whereNotNull('diploma_file_name')
                    ->orWhereNotNull('diploma_url');
                })
                ->get(['student_id', 'student_name', 'recipient_name', 'diploma_url', 'diploma_file_name']);
            foreach ($existingDiplomas as $existingDiploma) {
                $existingFileName = $this->normalizedDiplomaFileName(
                    $existingDiploma->diploma_file_name ?: $existingDiploma->diploma_url
                );
                if ($existingFileName !== '') {
                    $existingFileOwners[$existingFileName] ??= $this->studentOwnerLabel($existingDiploma);
                }
            }
            foreach ($batchFileOwners as $fileName => $owner) {
                if (isset($existingFileOwners[$fileName])) {
                    return response()->json([
                        'message' => 'Diploma image "' . $fileName . '" already belongs to ' . $existingFileOwners[$fileName] . '. Choose another image file.',
                    ], 422);
                }
            }
        }

        $records = $certificates->map(function (array $certificate) use ($universityCode) {
            $diplomaFileName = $this->normalizedDiplomaFileName(
                ($certificate['diploma_file_name'] ?? '') ?: ($certificate['diploma_url'] ?? null)
            );
            unset($certificate['additional_degree']);

            return array_merge($certificate, [
                'student_id' => trim($certificate['student_id']),
                'student_email' => strtolower(trim($certificate['student_email'])),
                'email' => strtolower(trim($certificate['student_email'])),
                'diploma_file_name' => $diplomaFileName ?: null,
                'degree_number' => (int) ($certificate['degree_number'] ?? 1),
                'certificate_code' => 'CERT-' . strtoupper(Str::random(10)),
                'recipient_name' => $certificate['student_name'],
                'course_or_event' => $certificate['degree'],
                'university_code' => $universityCode,
                'status' => 'Verified',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        })->all();

        DB::transaction(fn () => Certificate::insert($records));

        $issuedCertificates = Certificate::query()
            ->whereIn('certificate_code', array_column($records, 'certificate_code'))
            ->get();
        foreach ($issuedCertificates as $certificate) {
            $this->anchorCertificate($blockchain, $certificate);
        }

        return response()->json([
            'message' => 'Certificates issued.',
            'count' => count($records),
            'data' => $issuedCertificates->fresh(),
        ], 201);
    }

    private function anchorCertificate(BlockchainRegistryService $blockchain, Certificate $certificate): array
    {
        try {
            $result = $blockchain->issueCertificate(
                (string) $certificate->cert_hash,
                (string) ($certificate->student_name ?: $certificate->recipient_name),
                (string) $certificate->degree,
                (string) $certificate->issue_date,
            );
        } catch (\Throwable $exception) {
            Log::warning('Blockchain credential submission failed.', [
                'certificate_id' => $certificate->id,
                'exception' => $exception->getMessage(),
            ]);
            $result = [
                'status' => 'failed',
                'error' => 'Blockchain submission failed. The certificate remains in the application database.',
            ];
        }

        $certificate->forceFill([
            'blockchain_status' => $result['status'],
            'blockchain_tx_hash' => $result['transaction_hash'] ?? null,
            'blockchain_network' => $result['network'] ?? null,
            'blockchain_error' => $result['error'] ?? null,
        ])->save();

        return $result;
    }

    public function checkDiplomaFileNames(Request $request)
    {
        $user = $request->user();
        $validated = $request->validate([
            'file_names' => ['required', 'array', 'min:1'],
            'file_names.*' => ['required', 'string', 'max:255'],
            'university_code' => ['nullable', 'string', 'exists:universities,code'],
        ]);
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        $universityCode = $isSuperAdmin
            ? ($validated['university_code'] ?? null)
            : $user?->university_code;
        if ($user?->role !== 'admin' || !$universityCode) {
            return response()->json(['message' => 'An authorized administrator and university are required to validate diploma image names.'], 403);
        }

        $requestedNames = [];
        foreach ($validated['file_names'] as $fileName) {
            $normalizedName = $this->normalizedDiplomaFileName($fileName);
            if (isset($requestedNames[$normalizedName])) {
                return response()->json([
                    'message' => 'Diploma image "' . $normalizedName . '" is repeated in this batch. Choose a different image file for each student.',
                ], 422);
            }
            $requestedNames[$normalizedName] = true;
        }

        $existingDiplomas = Certificate::where('university_code', $universityCode)
            ->where(function ($query) {
            $query->whereNotNull('diploma_file_name')
                ->orWhereNotNull('diploma_url');
            })
            ->get(['student_id', 'student_name', 'recipient_name', 'diploma_url', 'diploma_file_name']);
        foreach ($existingDiplomas as $existingDiploma) {
            $existingFileName = $this->normalizedDiplomaFileName(
                $existingDiploma->diploma_file_name ?: $existingDiploma->diploma_url
            );
            if (isset($requestedNames[$existingFileName])) {
                return response()->json([
                    'message' => 'Diploma image "' . $existingFileName . '" already belongs to ' . $this->studentOwnerLabel($existingDiploma) . '. Choose another image file.',
                ], 422);
            }
        }

        return response()->json(['message' => 'Diploma image file names are available.']);
    }

    public function validateBatchIssuance(Request $request)
    {
        $user = $request->user();
        $validated = $request->validate([
            'certificates' => ['required', 'array', 'min:1'],
            'university_code' => ['nullable', 'string', 'exists:universities,code'],
            'certificates.*.student_id' => ['required', 'string', 'max:255'],
            'certificates.*.student_name' => ['required', 'string', 'max:255'],
            'certificates.*.student_email' => ['required', 'email'],
            'certificates.*.diploma_file_name' => ['nullable', 'string', 'max:255'],
            'certificates.*.additional_degree' => ['nullable', 'boolean'],
            'certificates.*.degree_number' => ['nullable', 'integer', 'min:1', 'max:65535'],
        ]);
        $isSuperAdmin = strtolower((string) $user?->email) === 'certitrust256@gmail.com';
        $universityCode = $isSuperAdmin
            ? ($validated['university_code'] ?? null)
            : $user?->university_code;
        if ($user?->role !== 'admin' || !$universityCode) {
            return response()->json(['message' => 'An authorized administrator and university are required to validate credential issuance.'], 403);
        }

        $certificates = collect($validated['certificates']);
        $batchStudentOwners = [];
        foreach ($certificates as $certificate) {
            $studentId = strtolower(trim($certificate['student_id']));
            $owner = ($certificate['student_name'] ?: 'Student') . ' (Student ID ' . trim($certificate['student_id']) . ')';
            if (isset($batchStudentOwners[$studentId])) {
                return response()->json([
                    'message' => 'Student ID "' . trim($certificate['student_id']) . '" is repeated in this batch and already belongs to ' . $batchStudentOwners[$studentId] . '.',
                ], 422);
            }
            $batchStudentOwners[$studentId] = $owner;
        }

        $additionalDegreeCandidates = [];
        foreach ($certificates as $index => $certificate) {
            $existingStudent = $this->findStudentByIds([
                strtolower(trim($certificate['student_id'])),
            ], $universityCode);
            $isAdditionalDegree = (bool) ($certificate['additional_degree'] ?? false);
            if ($existingStudent && !$isAdditionalDegree) {
                $degreeRecords = Certificate::where('university_code', $universityCode)
                    ->whereRaw('LOWER(TRIM(student_id)) = ?', [strtolower(trim($certificate['student_id']))])
                    ->orderBy('degree_number')
                    ->get(['degree', 'degree_number']);
                $additionalDegreeCandidates[] = [
                    'draft_index' => $index,
                    'student_name' => $certificate['student_name'],
                    'student_id' => $certificate['student_id'],
                    'existing_degrees' => $degreeRecords->map(fn (Certificate $degree) => [
                        'degree' => $degree->degree,
                        'degree_number' => $degree->degree_number,
                    ])->values(),
                    'next_degree_number' => $this->nextDegreeNumber(
                        $universityCode,
                        $certificate['student_id'],
                    ),
                ];
            } elseif ($existingStudent && $isAdditionalDegree) {
                if ((int) ($certificate['degree_number'] ?? 0) !== $this->nextDegreeNumber(
                    $universityCode,
                    $certificate['student_id'],
                )) {
                    return response()->json([
                        'message' => 'The degree number changed because another credential was issued. Please try again.',
                    ], 422);
                }
            } elseif ($isAdditionalDegree || (int) ($certificate['degree_number'] ?? 1) !== 1) {
                return response()->json([
                    'message' => 'An additional degree must refer to a student with an existing credential.',
                ], 422);
            }
        }

        $emails = $certificates->map(fn (array $certificate) => strtolower(trim($certificate['student_email'])));
        if ($emails->duplicates()->isNotEmpty()) {
            return response()->json([
                'message' => 'A Google email is repeated in this batch. Each student must use a unique email.',
            ], 422);
        }
        foreach ($emails as $email) {
            $emailOwner = $this->findStudentByEmail($email);
            if ($emailOwner) {
                $emailCertificate = DB::table('certificates')
                    ->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email])
                    ->first(['student_id', 'university_code']);
                $batchCredential = $certificates->first(
                    fn (array $certificate) => strtolower(trim($certificate['student_email'])) === $email
                );
                if (
                    $batchCredential
                    && $emailCertificate
                    && strtolower(trim((string) $emailCertificate->student_id))
                        === strtolower(trim($batchCredential['student_id']))
                    && $emailCertificate->university_code === $universityCode
                ) {
                    continue;
                }
                return response()->json([
                    'message' => $this->emailConflictMessage($email, $emailOwner, $universityCode),
                ], 422);
            }
        }

        $requestedFileNames = [];
        foreach ($certificates as $certificate) {
            $fileName = $this->normalizedDiplomaFileName($certificate['diploma_file_name'] ?? null);
            if ($fileName === '') {
                continue;
            }
            if (isset($requestedFileNames[$fileName])) {
                return response()->json([
                    'message' => 'Diploma image "' . $fileName . '" is repeated in this batch. Choose a different image file for each student.',
                ], 422);
            }
            $requestedFileNames[$fileName] = true;
        }
        if ($requestedFileNames !== []) {
            $existingDiplomas = Certificate::where('university_code', $universityCode)
                ->where(function ($query) {
                    $query->whereNotNull('diploma_file_name')
                        ->orWhereNotNull('diploma_url');
                })
                ->get(['student_id', 'student_name', 'recipient_name', 'diploma_url', 'diploma_file_name']);
            foreach ($existingDiplomas as $existingDiploma) {
                $fileName = $this->normalizedDiplomaFileName(
                    $existingDiploma->diploma_file_name ?: $existingDiploma->diploma_url
                );
                if (isset($requestedFileNames[$fileName])) {
                    return response()->json([
                        'message' => 'Diploma image "' . $fileName . '" already belongs to ' . $this->studentOwnerLabel($existingDiploma) . '. Choose another image file.',
                    ], 422);
                }
            }
        }

        $warnings = [];
        $normalizedNames = $certificates
            ->map(fn (array $certificate) => strtolower(trim($certificate['student_name'])))
            ->filter()
            ->unique();
        foreach ($normalizedNames as $name) {
            $otherUniversities = Certificate::whereRaw('LOWER(TRIM(student_name)) = ?', [$name])
                ->where('university_code', '!=', $universityCode)
                ->distinct()
                ->pluck('university_code')
                ->filter()
                ->values();
            if ($otherUniversities->isNotEmpty()) {
                $warnings[] = 'The name "' . $certificates->first(
                    fn (array $certificate) => strtolower(trim($certificate['student_name'])) === $name
                )['student_name'] . '" is also used at ' . $otherUniversities->implode(', ')
                    . '. Same names are allowed; you may continue.';
            }
        }

        return response()->json([
            'warnings' => $warnings,
            'additional_degree_candidates' => $additionalDegreeCandidates,
        ]);
    }

    private function nextDegreeNumber(string $universityCode, string $studentId): int
    {
        return (int) Certificate::where('university_code', $universityCode)
            ->whereRaw('LOWER(TRIM(student_id)) = ?', [strtolower(trim($studentId))])
            ->max('degree_number') + 1;
    }

    private function studentOwnerLabel(object $certificate): string
    {
        $name = $certificate->student_name ?: $certificate->recipient_name ?: 'Student';
        $studentId = trim((string) ($certificate->student_id ?? ''));

        return $studentId === '' ? $name : $name . ' (Student ID ' . $studentId . ')';
    }

    private function findStudentByIds(
        array $studentIds,
        string $universityCode,
    ): ?Certificate {
        if ($studentIds === []) {
            return null;
        }
        $studentIds = array_map('strval', $studentIds);
        $placeholders = implode(', ', array_fill(0, count($studentIds), '?'));

        return Certificate::where('university_code', $universityCode)
            ->whereRaw(
                'LOWER(TRIM(student_id)) IN (' . $placeholders . ')',
                $studentIds,
            )
            ->first();
    }

    private function findStudentByEmail(string $email): ?object
    {
        $normalizedEmail = strtolower(trim($email));
        $certificate = DB::table('certificates')
            ->whereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail])
            ->orWhereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail])
            ->first(['student_name', 'recipient_name', 'student_id', 'university_code']);
        if ($certificate) {
            return $certificate;
        }

        return User::where('role', 'admin')
            ->whereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail])
            ->first(['name', 'university_code', 'email']);
    }

    private function emailConflictMessage(string $email, object $owner, string $currentUniversity): string
    {
        $ownerName = $owner->student_name ?? $owner->recipient_name ?? $owner->name ?? 'an existing account';
        $university = $owner->university_code ?? null;
        $location = $university && $university !== $currentUniversity ? ' at ' . $university : '';

        return 'Google email "' . $email . '" is already linked to ' . $ownerName . $location . '. Each student must use a unique email.';
    }

    private function normalizedDiplomaFileName(?string $value): string
    {
        if ($value === null || trim($value) === '') {
            return '';
        }

        $path = str_contains($value, '://')
            ? (parse_url($value, PHP_URL_PATH) ?: $value)
            : $value;
        $path = str_replace('\\', '/', $path);

        return strtolower(trim(rawurldecode(basename($path))));
    }

    public function storeWithFile(Request $request)
    {
        return $this->store($request);
    }

    /**
     * Handle Google Authentication from Flutter App or Web
     */
    public function googleLogin(Request $request)
    {
        try {
            $request->validate([
                'id_token' => 'nullable|string',
                'access_token' => 'nullable|string',
                'idToken' => 'nullable|string',
                'accessToken' => 'nullable|string',
            ]);

            $idToken = $request->input('id_token') ?: $request->input('idToken');
            $accessToken = $request->input('access_token') ?: $request->input('accessToken');
            $email = null;
            $name = $request->input('name', 'Google User');
            $googleId = null;

            // Approach 1: Try decoding/verifying as a Google JWT ID Token (Mobile)
            if ($idToken) {
                try {
                    if (class_exists(\Google_Client::class)) {
                        $client = new \Google_Client(['client_id' => env('GOOGLE_CLIENT_ID')]);
                        $payload = $client->verifyIdToken($idToken);
                        if ($payload) {
                            $email = $payload['email'] ?? null;
                            $name = $payload['name'] ?? $name;
                            $googleId = $payload['sub'] ?? null;
                        }
                    }
                } catch (\Exception $e) {
                    // Fallback manual JWT decoding if Google_Client fails or isn't installed
                    $tokenParts = explode('.', $idToken);
                    if (count($tokenParts) >= 2) {
                        $payload = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $tokenParts[1])), true);
                        $email = $payload['email'] ?? null;
                        $name = $payload['name'] ?? $name;
                        $googleId = $payload['sub'] ?? null;
                    }
                }
            }

            // Approach 2: If $email is still null, query Google UserInfo API using Access Token (with SSL bypass for local dev)
            if (!$email && ($accessToken || $idToken)) {
                $tokenToVerify = $accessToken ?: $idToken;
                
                $response = Http::withoutVerifying()
                    ->withToken($tokenToVerify)
                    ->get('https://www.googleapis.com/oauth2/v3/userinfo');

                if ($response->successful()) {
                    $googleUser = $response->json();
                    $email = $googleUser['email'] ?? null;
                    $name = $googleUser['name'] ?? $name;
                    $googleId = $googleUser['sub'] ?? null;
                }
            }

            if (!$email) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid Google authentication token or email could not be resolved.',
                ], 401);
            }

            $googleId = $googleId ?? ('google_' . md5($email));

            $user = User::whereRaw('LOWER(email) = ?', [strtolower($email)])->first();

            if (!$user) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This Google account is not registered in CertiTrust yet. Only the Super Admin is seeded by default; all other accounts must be created by the system admin.',
                ], 403);
            }

            if (!$user->google_id) {
                $user->update(['google_id' => $googleId]);
            }

            // Check if user is registered in your certificates table
            $hasCertificate = DB::table('certificates')->where('email', $email)->exists();
            $role = $user->role ?? 'student';

            // Generate a Sanctum token for API authentication
            $token = $user->createToken('CertiTrustMobileToken')->plainTextToken;

            return response()->json([
                'status' => 'success',
                'message' => 'Successfully authenticated with Google.',
                'token' => $token,
                'email' => $user->email,
                'role' => $role,
                'has_certificate' => $hasCertificate,
                'user' => $user,
            ], 200);

        } catch (\Exception $e) {
            Log::error('Google Login Error: ' . $e->getMessage());

            return response()->json([
                'status' => 'error',
                'message' => 'Authentication failed on server.',
                'error' => $e->getMessage(),
            ], 500);
        }
    }
}