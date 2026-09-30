<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\AdminActionLog;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    /**
     * Handle standard email and password login.
     */
    public function login(Request $request)
    {
        try {
            $credentials = $request->validate([
                'email' => ['required', 'email'],
                'password' => ['required'],
            ]);

            if (!Auth::attempt($credentials)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid email or password.',
                ], 401);
            }

            $user = User::where('email', $request->email)->first();
            $hasCertificate = DB::table('certificates')
                ->where('email', $user->email)
                ->orWhere('student_email', $user->email)
                ->exists();
            $role = $user->role ?? 'student';

            // Generate Sanctum token
            $token = $user->createToken('CertiTrustMobileToken')->plainTextToken;

            return response()->json([
                'status' => 'success',
                'message' => 'Successfully logged in.',
                'token' => $token,
                'email' => $user->email,
                'role' => $role,
                'university_code' => $user->university_code,
                'has_certificate' => $hasCertificate,
                'user' => $user,
            ], 200);

        } catch (\Exception $e) {
            Log::error('Login Error: ' . $e->getMessage());

            return response()->json([
                'status' => 'error',
                'message' => 'Authentication failed on server.',
                'error' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Handle Google Authentication from Flutter App
     */
    public function googleLogin(Request $request)
    {
        try {
            $request->validate([
                'id_token' => 'nullable|string|required_without:access_token',
                'access_token' => 'nullable|string',
            ]);

            $googleData = $this->resolveGoogleUser($request);
            $email = $googleData['email'] ?? null;
            $name = $googleData['name'] ?? 'Google User';
            $googleId = $googleData['sub'] ?? null;

            if (!$email) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Email could not be resolved from the authentication payload.',
                ], 422);
            }

            $googleId = $googleId ?? ('google_' . md5($email));

            $normalizedEmail = strtolower(trim($email));
            $existingUser = User::whereRaw('LOWER(email) = ?', [$normalizedEmail])->first();
            $certificateQuery = DB::table('certificates')
                ->where(function ($query) use ($normalizedEmail) {
                    $query->whereRaw('LOWER(email) = ?', [$normalizedEmail])
                        ->orWhereRaw('LOWER(student_email) = ?', [$normalizedEmail]);
                });
            $certificate = (clone $certificateQuery)->latest('id')->first();
            $hasCertificate = $certificate !== null;

            if (!$existingUser && !$certificate && $normalizedEmail !== 'certitrust256@gmail.com') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This Google account is not registered in CertiTrust yet. Only the Super Admin is seeded by default; all other accounts must be created by the system admin.',
                ], 403);
            }

            if (!$existingUser && $normalizedEmail === 'certitrust256@gmail.com') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'The Super Admin account has not been created in the system yet.',
                ], 403);
            }

            if (!$existingUser && !$certificate) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This Google account is not registered in CertiTrust yet. Only the Super Admin is seeded by default; all other accounts must be created by the system admin.',
                ], 403);
            }

            $user = $existingUser;
            if (!$user && $certificate) {
                $user = User::create([
                    'name' => $certificate->student_name ?: $certificate->recipient_name ?: $name,
                    'email' => $normalizedEmail,
                    'password' => Hash::make(Str::random(40)),
                    'role' => 'student',
                    'university_code' => $certificate->university_code,
                ]);
            }

            if (!$user->google_id) {
                $user->update(['google_id' => $googleId]);
            }

            $role = $user->role ?? 'student';
            if (!$user->university_code && $certificate?->university_code) {
                $user->forceFill(['university_code' => $certificate->university_code])->save();
            }

            // Generate a Sanctum token for API authentication
            $token = $user->createToken('CertiTrustMobileToken')->plainTextToken;

            return response()->json([
                'status' => 'success',
                'message' => 'Successfully authenticated with Google.',
                'token' => $token,
                'email' => $user->email,
                'role' => $role,
                'university_code' => $user->university_code,
                'has_certificate' => $hasCertificate,
                'user' => $user,
            ], 200);

        } catch (\Exception $e) {
            Log::error('Google Login Error: ' . $e->getMessage());

            $status = $e instanceof \InvalidArgumentException ? 401 : 500;

            return response()->json([
                'status' => 'error',
                'message' => 'Authentication failed on server.',
                'error' => $e->getMessage(),
            ], $status);
        }
    }

    /**
     * Create a university administrator from the Super Admin console.
     */
    public function createAdmin(Request $request)
    {
        if (strtolower((string) $request->user()?->email) !== 'certitrust256@gmail.com') {
            return response()->json([
                'message' => 'Only the Super Admin can create administrator accounts.',
            ], 403);
        }

        $validated = $request->validate([
            'email' => ['required', 'email'],
            'university_code' => ['required', 'in:UCU,PSU'],
        ]);
        $email = strtolower(trim($validated['email']));
        if (User::whereRaw('LOWER(email) = ?', [$email])->exists()) {
            return response()->json([
                'message' => 'This email is already in use. Enter another email address.',
            ], 422);
        }
        if ($this->emailIsUsedByStudentCredential($email)) {
            return response()->json([
                'message' => 'This email is already linked to a student credential. Enter another email address.',
            ], 422);
        }

        $admin = User::create([
            'name' => 'University Admin',
            'email' => $email,
            'password' => Hash::make(Str::random(32)),
            'role' => 'admin',
            'university_code' => $validated['university_code'],
        ]);

        $this->logAdminAction(
            'created_subadmin',
            $admin->email,
            $admin->university_code,
            ['label' => 'Created university admin account']
        );

        return response()->json([
            'message' => 'Administrator account created successfully.',
            'admin' => $admin->only(['id', 'name', 'email', 'role', 'university_code']),
        ], 201);
    }

    public function listSubadmins(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $query = User::where('role', 'admin')
            ->whereNotNull('university_code');

        if ($request->filled('university_code')) {
            $query->where('university_code', $request->string('university_code')->toString());
        }

        return response()->json([
            'data' => $query->orderBy('university_code')->orderBy('email')->get([
                'id', 'name', 'email', 'role', 'university_code', 'google_id', 'created_at', 'updated_at',
            ]),
        ]);
    }

    public function bindSubadmin(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $validated = $request->validate([
            'university_code' => ['required', 'in:UCU,PSU'],
            'email' => ['required', 'email'],
            'name' => ['nullable', 'string', 'max:255'],
        ]);

        $existingAdmin = User::where('university_code', $validated['university_code'])
            ->where('role', 'admin')
            ->first();

        $email = strtolower(trim($validated['email']));
        if ($this->emailIsUsedByStudentCredential($email)) {
            return response()->json([
                'message' => 'This email is already linked to a student credential. Enter another email address.',
            ], 422);
        }
        $duplicateQuery = User::whereRaw('LOWER(email) = ?', [$email]);
        if ($existingAdmin) {
            $duplicateQuery->whereKeyNot($existingAdmin->id);
        }
        if ($duplicateQuery->exists()) {
            return response()->json([
                'message' => 'This email is already in use. Enter another email address.',
            ], 422);
        }

        if ($existingAdmin) {
            $previousEmail = $existingAdmin->email;
            $existingAdmin->forceFill([
                'email' => $email,
                'name' => $validated['name'] ?? $existingAdmin->name ?? 'University Admin',
                'role' => 'admin',
                'university_code' => $validated['university_code'],
            ])->save();

            $this->logAdminAction(
                'updated_subadmin',
                $existingAdmin->email,
                $existingAdmin->university_code,
                ['previous_email' => $previousEmail, 'label' => 'Replaced university admin Google account']
            );

            return response()->json([
                'message' => 'University subadmin account updated successfully.',
                'data' => $existingAdmin->fresh(),
            ]);
        }

        $admin = User::create([
            'name' => $validated['name'] ?? 'University Admin',
            'email' => $email,
            'password' => Hash::make(Str::random(32)),
            'role' => 'admin',
            'university_code' => $validated['university_code'],
        ]);

        $this->logAdminAction(
            'created_subadmin',
            $admin->email,
            $admin->university_code,
            ['label' => 'Bound university admin Google account']
        );

        return response()->json([
            'message' => 'University subadmin account created successfully.',
            'data' => $admin,
        ], 201);
    }

    public function updateSubadmin(Request $request, User $user)
    {
        $this->ensureSuperAdmin($request);

        if ($user->role !== 'admin' || !$user->university_code) {
            return response()->json(['message' => 'Only university admin records can be updated here.'], 422);
        }

        $validated = $request->validate([
            'email' => ['sometimes', 'required', 'email'],
            'name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'university_code' => ['sometimes', 'required', 'in:UCU,PSU'],
        ]);

        $nextEmail = isset($validated['email']) ? strtolower(trim($validated['email'])) : $user->email;

        $duplicateOwner = User::whereRaw('LOWER(email) = ?', [$nextEmail])
            ->whereKeyNot($user->id)
            ->first();

        if ($duplicateOwner || $this->emailIsUsedByStudentCredential($nextEmail)) {
            return response()->json([
                'message' => 'This email is already in use. Enter another email address.',
            ], 422);
        }

        $previousEmail = $user->email;
        $user->fill([
            'email' => $nextEmail,
            'name' => $validated['name'] ?? $user->name,
            'university_code' => $validated['university_code'] ?? $user->university_code,
            'role' => 'admin',
        ]);

        $user->save();

        $this->logAdminAction(
            'updated_subadmin',
            $user->email,
            $user->university_code,
            ['previous_email' => $previousEmail, 'label' => 'Updated university admin account']
        );

        return response()->json([
            'message' => 'University subadmin account updated successfully.',
            'data' => $user->fresh(),
        ]);
    }

    public function unbindSubadminGoogle(Request $request, User $user)
    {
        $this->ensureSuperAdmin($request);

        if ($user->role !== 'admin' || !$user->university_code) {
            return response()->json(['message' => 'Only university admin records can have their Google binding removed here.'], 422);
        }

        $user->forceFill([
            'google_id' => null,
            'updated_at' => now(),
        ])->save();

        $this->logAdminAction(
            'removed_google_binding',
            $user->email,
            $user->university_code,
            ['label' => 'Removed bound Google account']
        );

        return response()->json([
            'message' => 'Google account binding removed successfully.',
            'data' => $user->fresh(),
        ]);
    }

    public function deleteSubadmin(Request $request, User $user)
    {
        $this->ensureSuperAdmin($request);

        if ($user->role !== 'admin') {
            return response()->json(['message' => 'Only university admin records can be deleted here.'], 422);
        }

        $universityCode = $user->university_code;
        $targetEmail = $user->email;
        $userId = $user->id;
        $user->delete();

        $this->logAdminAction(
            'deleted_subadmin',
            $targetEmail,
            $universityCode,
            ['label' => 'Deleted university admin account', 'deleted_user_id' => $userId]
        );

        return response()->json([
            'message' => 'University subadmin account removed successfully.',
            'data' => [
                'university_code' => $universityCode,
                'deleted_user_id' => $userId,
            ],
        ]);
    }

    public function adminActionHistory(Request $request)
    {
        $this->ensureSuperAdmin($request);

        if (!Schema::hasTable('admin_action_logs')) {
            return response()->json(['data' => []]);
        }

        return response()->json([
            'data' => AdminActionLog::latest('created_at')
                ->limit(50)
                ->get()
                ->map(fn ($item) => [
                    'id' => $item->id,
                    'action' => $item->action,
                    'actor_email' => $item->actor_email,
                    'target_email' => $item->target_email,
                    'university_code' => $item->university_code,
                    'details' => $item->details,
                    'created_at' => $item->created_at?->toISOString(),
                ])
                ->values(),
        ]);
    }

    public function superAdminOverview(Request $request)
    {
        if (strtolower((string) $request->user()?->email) !== 'certitrust256@gmail.com') {
            return response()->json(['message' => 'Only the Super Admin can view global activity.'], 403);
        }

        $certificates = DB::table('certificates')->latest('created_at')->limit(50)->get();
        $admins = User::where('role', 'admin')
            ->orderBy('university_code')
            ->get(['id', 'name', 'email', 'role', 'university_code', 'last_seen_at']);

        $universities = User::whereNotNull('university_code')
            ->where('university_code', '!=', '')
            ->select('university_code')
            ->distinct()
            ->orderBy('university_code')
            ->get()
            ->map(fn ($user) => [
                'code' => $user->university_code,
                'name' => $this->universityDisplayName($user->university_code),
            ])
            ->values();

        $history = Schema::hasTable('admin_action_logs')
            ? AdminActionLog::latest('created_at')
                ->limit(20)
                ->get()
                ->map(fn ($entry) => [
                    'id' => $entry->id,
                    'action' => $entry->action,
                    'actor_email' => $entry->actor_email,
                    'target_email' => $entry->target_email,
                    'university_code' => $entry->university_code,
                    'details' => $entry->details,
                    'created_at' => $entry->created_at?->toISOString(),
                ])
                ->values()
            : collect();

        return response()->json([
            'data' => [
                'total_universities' => $universities->count(),
                'universities' => $universities,
                'total_credentials' => DB::table('certificates')->count(),
                'verified_credentials' => DB::table('certificates')->where('status', 'Verified')->count(),
                'pending_actions' => 0,
                'admins' => $admins,
                'activity' => $certificates,
                'history' => $history,
            ],
        ]);
    }

    private function ensureSuperAdmin(Request $request): void
    {
        if (strtolower((string) $request->user()?->email) !== 'certitrust256@gmail.com') {
            abort(response()->json([
                'message' => 'Only the Super Admin can manage university subadmin accounts.',
            ], 403));
        }
    }

    private function logAdminAction(string $action, ?string $targetEmail, ?string $universityCode, array $details = []): void
    {
        if (!Schema::hasTable('admin_action_logs')) {
            Schema::create('admin_action_logs', function ($table) {
                $table->id();
                $table->string('actor_email')->nullable();
                $table->string('action');
                $table->string('target_email')->nullable();
                $table->string('university_code')->nullable();
                $table->json('details')->nullable();
                $table->timestamps();
            });
        }

        AdminActionLog::create([
            'actor_email' => strtolower((string) request()->user()?->email ?? 'certitrust256@gmail.com'),
            'action' => $action,
            'target_email' => $targetEmail ? strtolower(trim($targetEmail)) : null,
            'university_code' => $universityCode ? strtoupper(trim($universityCode)) : null,
            'details' => $details,
        ]);
    }

    private function universityDisplayName(?string $code): string
    {
        return match (strtoupper((string) $code)) {
            'UCU' => 'Urdaneta City University',
            'PSU' => 'Pangasinan State University',
            default => $code ?: 'University',
        };
    }

    /**
     * Validate the credential with Google and return its verified profile.
     */
    private function resolveGoogleUser(Request $request): array
    {
        $idToken = $request->string('id_token')->value() ?: null;
        $accessToken = $request->string('access_token')->value() ?: null;

        if ($idToken) {
            $response = $this->googleHttp()->get('https://oauth2.googleapis.com/tokeninfo', [
                'id_token' => $idToken,
            ]);

            if ($response->successful()) {
                $data = $response->json();
                $clientIds = array_filter(array_map('trim', explode(',', (string) env('GOOGLE_CLIENT_IDS', env('GOOGLE_CLIENT_ID', '')))));
                $expectedClientIds = $clientIds !== [] ? $clientIds : [(string) env('GOOGLE_CLIENT_ID', '')];
                $aud = (string) ($data['aud'] ?? '');
                $azp = (string) ($data['azp'] ?? '');

                if ($aud !== '' || $azp !== '') {
                    $matchesExpectedClient = in_array($aud, $expectedClientIds, true) || in_array($azp, $expectedClientIds, true);
                    if (!$matchesExpectedClient && !empty($expectedClientIds[0])) {
                        $fallbackResponse = $this->googleHttp()
                            ->withToken($accessToken ?? $idToken)
                            ->get('https://www.googleapis.com/oauth2/v3/userinfo');

                        if ($fallbackResponse->successful()) {
                            $fallbackData = $fallbackResponse->json();
                            if (!empty($fallbackData['email'])) {
                                return $fallbackData;
                            }
                        }

                        throw new \InvalidArgumentException('Google ID token audience does not match this application.');
                    }
                }

                if (($data['email_verified'] ?? 'false') !== 'true' && empty($data['email'])) {
                    throw new \InvalidArgumentException('Google email address is not verified.');
                }

                return $data;
            }

            if ($accessToken) {
                $response = $this->googleHttp()
                    ->withToken($accessToken)
                    ->get('https://www.googleapis.com/oauth2/v3/userinfo');

                if ($response->successful()) {
                    $data = $response->json();
                    if (!empty($data['email'])) {
                        return $data;
                    }
                }
            }

            throw new \InvalidArgumentException('Google ID token is invalid or expired.');
        }

        if (!$accessToken) {
            throw new \InvalidArgumentException('Google token payload is missing.');
        }

        $response = $this->googleHttp()
            ->withToken($accessToken)
            ->get('https://www.googleapis.com/oauth2/v3/userinfo');

        if (!$response->successful()) {
            throw new \InvalidArgumentException('Google access token is invalid or expired.');
        }

        $data = $response->json();
        if (empty($data['email']) || (($data['email_verified'] ?? 'false') !== 'true' && ($data['email_verified'] ?? false) !== true)) {
            throw new \InvalidArgumentException('Google account email could not be verified.');
        }

        return $data;
    }

    private function googleHttp()
    {
        return Http::timeout(10)->withOptions([
            'verify' => filter_var(env('GOOGLE_VERIFY_SSL', true), FILTER_VALIDATE_BOOLEAN),
        ]);
    }

    private function emailIsUsedByStudentCredential(string $email): bool
    {
        $normalizedEmail = strtolower(trim($email));

        return DB::table('certificates')
            ->where(function ($query) use ($normalizedEmail) {
                $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail]);
            })
            ->exists();
    }

    /**
     * Verify Student ID Mapping Route
     */
    public function verifyStudentId(Request $request)
    {
        try {
            $request->validate([
                'email' => 'required|email',
                'student_id' => 'required|string',
            ]);

            if (strtolower(trim($request->user()->email)) !== strtolower(trim($request->input('email')))) {
                return response()->json([
                    'success' => false,
                    'message' => 'The authenticated account does not match this email address.',
                ], 403);
            }

            // Query certificates table to verify the mapping between email and student ID
            $certificate = DB::table('certificates')
                ->where(function ($query) use ($request) {
                    $query->whereRaw('LOWER(email) = ?', [strtolower(trim($request->email))])
                        ->orWhereRaw('LOWER(student_email) = ?', [strtolower(trim($request->email))]);
                })
                ->where('student_id', $request->student_id)
                ->first();

            if (!$certificate) {
                return response()->json([
                    'success' => false,
                    'message' => 'The Student ID does not match database records for this email.',
                ], 404);
            }

            return response()->json([
                'success' => true,
                'message' => 'Student ID verified successfully.',
                'certificate' => $certificate,
                'profile' => [
                    'profile_image_url' => $request->user()->profile_image_url,
                    'profile_icon' => $request->user()->profile_icon,
                ],
            ], 200);

        } catch (\Exception $e) {
            Log::error('Student ID Verification Error: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Server error during verification.',
                'error' => $e->getMessage(),
            ], 500);
        }
    }

    public function updateProfile(Request $request)
    {
        $validated = $request->validate([
            'profile_icon' => ['nullable', 'in:girl,boy'],
            'profile_image' => ['nullable', 'image', 'max:5120'],
        ]);

        if (!$request->hasFile('profile_image') && empty($validated['profile_icon'])) {
            return response()->json(['message' => 'Choose a profile photo or an avatar icon.'], 422);
        }

        $user = $request->user();
        if ($request->hasFile('profile_image')) {
            $path = $request->file('profile_image')->store('profiles', 'public');
            $validated['profile_image_url'] = Storage::disk('public')->url($path);
            $validated['profile_icon'] = null;
        } else {
            $validated['profile_image_url'] = null;
        }

        $user->forceFill([
            'profile_image_url' => $validated['profile_image_url'],
            'profile_icon' => $validated['profile_icon'] ?? null,
        ])->save();

        return response()->json([
            'profile_image_url' => $user->profile_image_url,
            'profile_icon' => $user->profile_icon,
        ]);
    }
}