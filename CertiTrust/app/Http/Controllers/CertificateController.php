<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use App\Models\User;
use App\Models\Certificate;
use App\Services\SupabaseDiplomaStorage;

class CertificateController extends Controller
{
    public function index(Request $request)
    {
        $query = Certificate::query()->latest('issue_date');
        $user = $request->user();
        if ($user?->role === 'student') {
            $email = strtolower(trim((string) $user->email));
            $query->where(function ($studentCertificates) use ($email) {
                $studentCertificates->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
            });
        } elseif ($user?->university_code) {
            $query->where('university_code', $user->university_code);
        }
        return response()->json(['data' => $query->get()]);
    }

    public function show(string $code)
    {
        $normalizedCode = trim($code);
        $certificate = Certificate::where('certificate_code', $normalizedCode)
            ->orWhereRaw('LOWER(cert_hash) = ?', [strtolower($normalizedCode)])
            ->first();

        return $certificate
            ? response()->json(['data' => $certificate])
            : response()->json(['message' => 'Certificate not found.'], 404);
    }

    public function uploadDiploma(Request $request, SupabaseDiplomaStorage $storage)
    {
        $user = $request->user();
        if ($user?->role !== 'admin' || !$user->university_code) {
            return response()->json(['message' => 'A school administrator is required to upload diploma files.'], 403);
        }

        $validated = $request->validate([
            'diploma_file' => ['required', 'file', 'mimes:pdf,png,jpg,jpeg', 'min:1', 'max:20480'],
        ]);
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

    public function store(Request $request)
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
            'university_code' => ['nullable', 'in:UCU,PSU'],
        ]);

        $universityCode = $request->user()?->university_code;
        if (!$universityCode || ($validated['university_code'] ?? $universityCode) !== $universityCode) {
            return response()->json(['message' => 'This admin is not authorized to issue for that school.'], 403);
        }
        $studentId = strtolower(trim($validated['student_id']));
        $existingStudent = $this->findStudentByIds($universityCode, [$studentId]);
        if ($existingStudent) {
            return response()->json([
                'message' => 'Student ID "' . trim($validated['student_id']) . '" already belongs to ' . $this->studentOwnerLabel($existingStudent) . '. Enter a unique Student ID.',
            ], 422);
        }
        $studentEmail = strtolower(trim($validated['student_email']));
        if ($this->studentEmailIsUnavailable($studentEmail)) {
            return response()->json([
                'message' => 'This Google email is already linked to a student or administrator account. Use a unique email.',
            ], 422);
        }
        $diplomaUrl = $validated['diploma_url'] ?? null;
        $diplomaFileName = $this->normalizedDiplomaFileName(
            ($validated['diploma_file_name'] ?? '') ?: $diplomaUrl
        );
        if ($diplomaFileName !== '') {
            $existingDiplomas = Certificate::where(function ($query) {
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

        return response()->json(['data' => Certificate::create($validated)], 201);
    }

    public function storeBatch(Request $request)
    {
        $validated = $request->validate([
            'certificates' => ['required', 'array', 'min:1'],
            'certificates.*.student_id' => ['required', 'string', 'max:255'],
            'certificates.*.student_name' => ['required', 'string', 'max:255'],
            'certificates.*.student_email' => ['required', 'email'],
            'certificates.*.degree' => ['required', 'string', 'max:255'],
            'certificates.*.issue_date' => ['required', 'date'],
            'certificates.*.cert_hash' => ['required', 'string'],
            'certificates.*.diploma_url' => ['nullable', 'url'],
            'certificates.*.diploma_file_name' => ['nullable', 'string', 'max:255'],
            'certificates.*.university_code' => ['nullable', 'in:UCU,PSU'],
        ]);

        $universityCode = $request->user()?->university_code;
        if (!$universityCode) {
            return response()->json(['message' => 'A registered school admin is required to issue credentials.'], 403);
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
        $studentIds = array_keys($batchStudentOwners);
        $existingStudent = $this->findStudentByIds($universityCode, $studentIds);
        if ($existingStudent) {
            return response()->json([
                'message' => 'Student ID "' . $existingStudent->student_id . '" already belongs to ' . $this->studentOwnerLabel($existingStudent) . '. Enter a unique Student ID.',
            ], 422);
        }
        $studentEmails = $certificates->map(fn (array $certificate) => strtolower(trim($certificate['student_email'])));
        if ($studentEmails->duplicates()->isNotEmpty()) {
            return response()->json([
                'message' => 'A Google email is repeated in this batch. Each student must use a unique email.',
            ], 422);
        }
        if (DB::table('certificates')->where(function ($query) use ($studentEmails) {
            $query->whereIn(DB::raw('LOWER(TRIM(student_email))'), $studentEmails->all())
                ->orWhereIn(DB::raw('LOWER(TRIM(email))'), $studentEmails->all());
        })->exists() || User::where('role', 'admin')
            ->whereIn(DB::raw('LOWER(TRIM(email))'), $studentEmails->all())
            ->exists()) {
            return response()->json([
                'message' => 'A Google email is already linked to a student or administrator account. Use a unique email.',
            ], 422);
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
            $existingDiplomas = Certificate::where(function ($query) {
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
            return array_merge($certificate, [
                'student_id' => trim($certificate['student_id']),
                'student_email' => strtolower(trim($certificate['student_email'])),
                'email' => strtolower(trim($certificate['student_email'])),
                'diploma_file_name' => $diplomaFileName ?: null,
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

        return response()->json(['message' => 'Certificates issued.', 'count' => count($records)], 201);
    }

    public function checkDiplomaFileNames(Request $request)
    {
        $user = $request->user();
        if ($user->role !== 'admin' || !$user->university_code) {
            return response()->json(['message' => 'Only a school administrator can validate diploma image names.'], 403);
        }

        $validated = $request->validate([
            'file_names' => ['required', 'array', 'min:1'],
            'file_names.*' => ['required', 'string', 'max:255'],
        ]);

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

        $existingDiplomas = Certificate::where(function ($query) {
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

    private function studentEmailIsUnavailable(string $email): bool
    {
        $normalizedEmail = strtolower(trim($email));

        return DB::table('certificates')->where(function ($query) use ($normalizedEmail) {
            $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail])
                ->orWhereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail]);
        })->exists() || User::where('role', 'admin')
            ->whereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail])
            ->exists();
    }

    private function studentOwnerLabel(object $certificate): string
    {
        $name = $certificate->student_name ?: $certificate->recipient_name ?: 'Student';
        $studentId = trim((string) ($certificate->student_id ?? ''));

        return $studentId === '' ? $name : $name . ' (Student ID ' . $studentId . ')';
    }

    private function findStudentByIds(string $universityCode, array $studentIds): ?Certificate
    {
        $existingStudent = Certificate::where('university_code', $universityCode)
            ->whereIn('student_id', $studentIds)
            ->first();
        if ($existingStudent) {
            return $existingStudent;
        }

        return Certificate::where('university_code', $universityCode)
            ->get(['student_id', 'student_name', 'recipient_name'])
            ->first(fn (Certificate $certificate) => in_array(
                strtolower(trim((string) $certificate->student_id)),
                $studentIds,
                true,
            ));
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