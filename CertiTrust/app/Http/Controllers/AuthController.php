<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\AdminActionLog;
use App\Models\UniversityAccessControl;
use App\Models\University;
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

            if (strtolower(trim($credentials['email'])) === 'certitrust256@gmail.com') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This account must sign in with Google.',
                ], 403);
            }

            if (!Auth::attempt($credentials)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid email or password.',
                ], 401);
            }

            $user = User::where('email', $request->email)->first();
            if ($user?->isAccessFrozen()) {
                Auth::logout();
                return $this->frozenLoginResponse($user, DB::table('certificates')
                    ->where(function ($query) use ($user) {
                        $query->where('email', $user->email)
                            ->orWhere('student_email', $user->email);
                    })
                    ->exists());
            }
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
            $existingUser = User::whereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail])->first();
            $certificateQuery = DB::table('certificates')
                ->where(function ($query) use ($normalizedEmail) {
                    $query->whereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail])
                        ->orWhereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail]);
                });
            $certificate = (clone $certificateQuery)->latest('id')->first();
            $hasCertificate = $certificate !== null;

            $isSuperAdmin = $normalizedEmail === 'certitrust256@gmail.com';
            if (!$existingUser && !$certificate && !$isSuperAdmin) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This Google account is not registered in CertiTrust yet. Please ask the system admin to create your account.',
                ], 403);
            }

            $user = $existingUser;
            if ($user?->isAccessFrozen()) {
                return $this->frozenLoginResponse($user, $hasCertificate);
            }
            if (!$user && $isSuperAdmin) {
                $user = User::create([
                    'name' => $name,
                    'email' => $normalizedEmail,
                    'password' => Hash::make(Str::random(64)),
                    'google_id' => $googleId,
                    'role' => 'admin',
                    'university_code' => null,
                ]);
            } elseif (!$user && $certificate) {
                $user = User::create([
                    'name' => $certificate->student_name ?: $certificate->recipient_name ?: $name,
                    'email' => $normalizedEmail,
                    'password' => Hash::make(Str::random(40)),
                    'role' => 'student',
                    'university_code' => $certificate->university_code,
                ]);
            }

            if ($isSuperAdmin) {
                $user->forceFill([
                    'password' => Hash::make(Str::random(64)),
                    'google_id' => $googleId,
                    'role' => 'admin',
                    'university_code' => null,
                ])->save();
            } elseif (!$user->google_id) {
                $user->update(['google_id' => $googleId]);
            }

            $role = $user->role ?? 'student';
            if (!$user->university_code && $certificate?->university_code) {
                $user->forceFill(['university_code' => $certificate->university_code])->save();
            }
            if ($user->isAccessFrozen()) {
                return $this->frozenLoginResponse($user, $hasCertificate);
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
            'university_code' => ['required', 'string', 'max:10', 'regex:/^[A-Z0-9]+$/', 'exists:universities,code'],
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

        $admins = $query->orderBy('university_code')->orderBy('email')->get([
            'id', 'name', 'email', 'role', 'university_code', 'google_id', 'access_frozen', 'created_at', 'updated_at',
        ]);
        $universityCodes = $admins->pluck('university_code')->filter()->unique()->values();
        $studentAccounts = User::whereIn('role', ['student', 'user'])
            ->whereIn('university_code', $universityCodes)
            ->orderBy('name')
            ->get([
                'id',
                'name',
                'email',
                'university_code',
                'access_frozen',
                'access_frozen_by',
            ]);
        $certificatesByStudentEmail = [];
        foreach (
            DB::table('certificates')
                ->whereIn('university_code', $universityCodes)
                ->orderByDesc('id')
                ->get([
                    'university_code',
                    'student_email',
                    'email',
                    'student_id',
                    'student_name',
                    'recipient_name',
                ]) as $certificate
        ) {
            $certificateEmails = array_unique([
                strtolower(trim((string) $certificate->student_email)),
                strtolower(trim((string) $certificate->email)),
            ]);
            foreach ($certificateEmails as $normalizedEmail) {
                if ($normalizedEmail === '') {
                    continue;
                }
                $key = $certificate->university_code . ':' . $normalizedEmail;
                $certificatesByStudentEmail[$key] ??= $certificate;
            }
        }
        $frozenStudentsByUniversity = [];
        foreach ($studentAccounts as $student) {
            if (!$student->isAccessFrozen()) {
                continue;
            }
            $key = $student->university_code . ':' . strtolower(trim((string) $student->email));
            $certificate = $certificatesByStudentEmail[$key] ?? null;
            $frozenStudentsByUniversity[$student->university_code][] = [
                'id' => $student->id,
                'name' => $certificate?->student_name
                    ?: $certificate?->recipient_name
                    ?: $student->name,
                'email' => $student->email,
                'student_id' => $certificate?->student_id ?: 'Not recorded',
                'freeze_owner_id' => $student->accessFrozenById(),
                'freeze_owner_email' => User::find($student->accessFrozenById())?->email,
            ];
        }

        return response()->json([
            'data' => $admins->map(function (User $admin) use ($frozenStudentsByUniversity) {
                $university = University::find($admin->university_code);
                return array_merge($admin->toArray(), [
                    'university_name' => $university?->university_name
                        ?: $this->universityDisplayName($admin->university_code),
                    'branch_campus' => $university?->branch_campus,
                    'display_name' => $university?->display_name
                        ?: $admin->university_code,
                    'frozen_students' => $frozenStudentsByUniversity[$admin->university_code] ?? [],
                ]);
            }),
        ]);
    }

    public function listUniversities(Request $request)
    {
        $this->ensureSuperAdmin($request);

        return response()->json([
            'data' => University::query()
                ->orderBy('university_name')
                ->orderBy('branch_campus')
                ->get()
                ->map(fn (University $university) => [
                    'code' => $university->code,
                    'university_name' => $university->university_name,
                    'branch_campus' => $university->branch_campus,
                    'display_name' => $university->display_name,
                ])
                ->values(),
        ]);
    }

    public function updateUniversityAccess(Request $request, string $universityCode)
    {
        $this->ensureSuperAdmin($request);
        abort_unless(University::whereKey($universityCode)->exists(), 404);

        $validated = $request->validate([
            'scope' => ['required', 'in:admin,students,both'],
            'frozen' => ['required', 'boolean'],
        ]);
        $frozen = (bool) $validated['frozen'];
        $scope = $validated['scope'];
        $admin = null;

        if (in_array($scope, ['admin', 'both'], true)) {
            $admin = User::where('role', 'admin')
                ->where('university_code', $universityCode)
                ->first();
            if (!$admin) {
                return response()->json([
                    'message' => 'No subadmin account is registered for this university.',
                ], 404);
            }
        }

        $actorId = (int) $request->user()->id;
        $protectedStudents = !$frozen && in_array($scope, ['students', 'both'], true)
            ? $this->studentsFrozenByOtherAdministrators($universityCode, $actorId)
            : [];
        if (!$frozen && $admin?->access_frozen) {
            if ((int) $admin->access_frozen_by !== $actorId) {
                return response()->json([
                    'message' => 'Only the administrator who froze this subadmin account can restore its access.',
                ], 403);
            }
        }
        if (in_array($scope, ['students', 'both'], true)) {
            $studentAccessControl = UniversityAccessControl::where(
                'university_code',
                $universityCode,
            )->first();
            if (
                $studentAccessControl?->students_frozen
                && (int) $studentAccessControl->updated_by !== $actorId
            ) {
                $protectedStudents = array_merge(
                    $protectedStudents,
                    $this->studentsFrozenByUniversityPolicy($universityCode),
                );
                return response()->json([
                    'message' => $frozen
                        ? 'Student access for this university is already frozen by another administrator.'
                        : 'Only the administrator who froze student access for this university can restore it.',
                    'protected_students' => $protectedStudents,
                ], 403);
            }
        }

        DB::transaction(function () use ($request, $universityCode, $scope, $frozen, $admin): void {
            if ($admin) {
                $admin->forceFill([
                    'access_frozen' => $frozen,
                    'access_frozen_at' => $frozen ? now() : null,
                    'access_frozen_by' => $frozen ? $request->user()->id : null,
                ])->save();
                if ($frozen) {
                    $admin->tokens()->delete();
                }
            }

            if (in_array($scope, ['students', 'both'], true)) {
                UniversityAccessControl::updateOrCreate(
                    ['university_code' => $universityCode],
                    [
                        'students_frozen' => $frozen,
                        'updated_by' => $request->user()->id,
                    ],
                );
                if ($frozen) {
                    User::whereIn('role', ['student', 'user'])
                        ->where('university_code', $universityCode)
                        ->where('access_frozen', false)
                        ->update([
                            'access_frozen' => null,
                            'access_frozen_at' => null,
                            'access_frozen_by' => null,
                        ]);
                    User::whereIn('role', ['student', 'user'])
                        ->where('university_code', $universityCode)
                        ->get()
                        ->each(fn (User $student) => $student->tokens()->delete());
                } else {
                    User::whereIn('role', ['student', 'user'])
                        ->where('university_code', $universityCode)
                        ->where('access_frozen', true)
                        ->where('access_frozen_by', $request->user()->id)
                        ->update([
                            'access_frozen' => false,
                            'access_frozen_at' => null,
                            'access_frozen_by' => null,
                        ]);
                }
            }
        });

        $this->logAdminAction(
            $frozen ? 'froze_university_access' : 'unfroze_university_access',
            $admin?->email,
            $universityCode,
            ['scope' => $scope, 'frozen' => $frozen],
        );

        return response()->json([
            'message' => $frozen ? 'Selected university access has been frozen.' : 'Selected university access has been restored.',
            'scope' => $scope,
            'frozen' => $frozen,
            'protected_students' => $protectedStudents,
        ]);
    }

    private function studentsFrozenByOtherAdministrators(
        string $universityCode,
        int $actorId,
    ): array {
        return User::whereIn('role', ['student', 'user'])
            ->where('university_code', $universityCode)
            ->where('access_frozen', true)
            ->where(function ($query) use ($actorId) {
                $query->whereNull('access_frozen_by')
                    ->orWhere('access_frozen_by', '!=', $actorId);
            })
            ->orderBy('name')
            ->get(['name', 'email'])
            ->map(fn (User $student) => $this->studentFreezeDetails($student))
            ->all();
    }

    private function studentsFrozenByUniversityPolicy(string $universityCode): array
    {
        return User::whereIn('role', ['student', 'user'])
            ->where('university_code', $universityCode)
            ->whereNull('access_frozen')
            ->orderBy('name')
            ->get(['name', 'email'])
            ->map(fn (User $student) => $this->studentFreezeDetails($student))
            ->all();
    }

    private function studentFreezeDetails(User $student): array
    {
        $email = strtolower(trim((string) $student->email));
        $certificate = DB::table('certificates')
            ->where(function ($query) use ($email) {
                $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
            })
            ->latest('id')
            ->first(['student_name', 'recipient_name', 'student_id']);

        return [
            'name' => $certificate?->student_name
                ?: $certificate?->recipient_name
                ?: $student->name,
            'student_id' => $certificate?->student_id ?: 'Not recorded',
        ];
    }

    public function listUniversityStudents(Request $request)
    {
        $admin = $request->user();
        if ($admin->role !== 'admin' || !$admin->university_code || $this->isSuperAdmin($admin)) {
            return response()->json([
                'message' => 'Only a university subadmin can manage student access.',
            ], 403);
        }

        return $this->universityStudentsResponse($admin->university_code, $admin);
    }

    public function listStudentsForUniversity(Request $request, string $universityCode)
    {
        $this->ensureSuperAdmin($request);
        abort_unless(University::whereKey($universityCode)->exists(), 404);

        return $this->universityStudentsResponse($universityCode, $request->user());
    }

    private function universityStudentsResponse(string $universityCode, User $actor)
    {
        $universityAccessControl = UniversityAccessControl::where(
            'university_code',
            $universityCode,
        )->first();
        $certificatesByStudentEmail = [];
        foreach (
            DB::table('certificates')
                ->where('university_code', $universityCode)
                ->orderByDesc('issue_date')
                ->orderByDesc('id')
                ->get([
                    'student_email',
                    'email',
                    'student_id',
                    'degree',
                    'course_or_event',
                    'degree_number',
                    'certificate_code',
                    'issue_date',
                ]) as $certificate
        ) {
            $emails = array_unique([
                strtolower(trim((string) $certificate->student_email)),
                strtolower(trim((string) $certificate->email)),
            ]);
            foreach ($emails as $normalizedEmail) {
                if ($normalizedEmail === '') {
                    continue;
                }
                $certificatesByStudentEmail[$normalizedEmail] ??= [];
                $certificatesByStudentEmail[$normalizedEmail][] = $certificate;
            }
        }
        $university = University::find($universityCode);
        $studentAccounts = User::whereIn('role', ['student', 'user'])
            ->where('university_code', $universityCode)
            ->orderBy('name')
            ->get([
                'id',
                'name',
                'email',
                'university_code',
                'access_frozen',
                'access_frozen_by',
                'created_at',
            ]);
        $policyOwnerId = $universityAccessControl?->students_frozen
            ? (int) $universityAccessControl->updated_by
            : null;
        $freezeOwnerIds = $studentAccounts
            ->map(fn (User $student) => $student->access_frozen === true
                ? $student->access_frozen_by
                : ($student->access_frozen === null ? $policyOwnerId : null))
            ->filter()
            ->unique()
            ->values();
        $freezeOwners = User::whereIn('id', $freezeOwnerIds)
            ->get(['id', 'name', 'email'])
            ->keyBy('id');
        $students = $studentAccounts->map(function (User $student) use (
                $actor,
                $university,
                $policyOwnerId,
                $universityAccessControl,
                $certificatesByStudentEmail,
                $freezeOwners,
            ) {
                $certificates = $certificatesByStudentEmail[
                    strtolower(trim((string) $student->email))
                ] ?? [];
                $latestCertificate = $certificates[0] ?? null;
                $credentialRecords = collect($certificates)
                    ->values()
                    ->map(function ($certificate, int $index) use ($certificates): array {
                        $degree = $certificate->degree ?: $certificate->course_or_event;
                        $degreeNumber = (int) ($certificate->degree_number
                            ?: count($certificates) - $index);

                        return [
                            'degree' => $degree,
                            'degree_number' => $degreeNumber,
                            'degree_type' => $this->degreeType($degree),
                            'issue_date' => $certificate->issue_date,
                            'certificate_code' => $certificate->certificate_code,
                        ];
                    })
                    ->sortBy('degree_number')
                    ->values();
                $freezeOwnerId = $student->access_frozen === true
                    ? (int) $student->access_frozen_by
                    : ($student->access_frozen === null
                        && $policyOwnerId
                        ? $policyOwnerId
                        : null);
                $isFrozen = $student->access_frozen === true
                    || ($student->access_frozen === null
                        && (bool) $universityAccessControl?->students_frozen);
                $freezeOwner = $freezeOwnerId ? $freezeOwners->get($freezeOwnerId) : null;

                return [
                    'id' => $student->id,
                    'name' => $student->name,
                    'email' => $student->email,
                    'university_code' => $student->university_code,
                    'university_name' => $university?->university_name
                        ?: $this->universityDisplayName($student->university_code),
                    'branch_campus' => $university?->branch_campus,
                    'display_name' => $university?->display_name
                        ?: $student->university_code,
                    'student_id' => $latestCertificate?->student_id,
                    'degree' => $latestCertificate?->degree
                        ?: $latestCertificate?->course_or_event,
                    'degrees' => collect($certificates)
                        ->map(fn ($certificate) => $certificate->degree
                            ?: $certificate->course_or_event)
                        ->filter()
                        ->unique()
                        ->values(),
                    'credentials' => $credentialRecords,
                    'certificate_code' => $latestCertificate?->certificate_code,
                    'issue_date' => $latestCertificate?->issue_date,
                    'batch_year' => $latestCertificate?->issue_date
                        ? substr((string) $latestCertificate->issue_date, 0, 4)
                        : $student->created_at?->format('Y'),
                    'credential_search' => collect($certificates)
                        ->flatMap(fn ($certificate) => [
                            $certificate->student_id,
                            $certificate->degree,
                            $certificate->course_or_event,
                            $certificate->certificate_code,
                        ])
                        ->filter()
                        ->unique()
                        ->implode(' '),
                    'is_frozen' => $isFrozen,
                    'freeze_owner_id' => $freezeOwnerId,
                    'freeze_owner_email' => $freezeOwner?->email,
                    'freeze_owner_name' => $freezeOwner?->name,
                    'can_manage_access' => !$isFrozen
                        || $freezeOwnerId === (int) $actor->id,
                ];
            });
        $actorIsSuperAdmin = $this->isSuperAdmin($actor);
        $canManageUniversityFreeze = !$universityAccessControl?->students_frozen
            || (int) $universityAccessControl->updated_by === (int) $actor->id;

        return response()->json([
            'data' => $students,
            'university_code' => $universityCode,
            'university_students_frozen' => (bool) $universityAccessControl?->students_frozen,
            'university_freeze_owner_id' => $universityAccessControl?->updated_by,
            'can_manage_university_freeze' => $canManageUniversityFreeze,
            'is_super_admin_view' => $actorIsSuperAdmin,
        ]);
    }

    public function updateStudentAccess(Request $request, User $user)
    {
        $admin = $request->user();
        $isSuperAdmin = $this->isSuperAdmin($admin);
        if (!$isSuperAdmin && ($admin->role !== 'admin' || !$admin->university_code)) {
            return response()->json([
                'message' => 'Only an administrator can manage student access.',
            ], 403);
        }
        if (
            !in_array($user->role, ['student', 'user'], true)
            || (!$isSuperAdmin && $user->university_code !== $admin->university_code)
        ) {
            return response()->json([
                'message' => $isSuperAdmin
                    ? 'Only student accounts can be managed here.'
                    : 'You may only manage student accounts from your university.',
            ], 403);
        }

        $validated = $request->validate(['frozen' => ['required', 'boolean']]);
        $frozen = (bool) $validated['frozen'];
        $universityPolicy = UniversityAccessControl::where(
            'university_code',
            $user->university_code,
        )->first();
        if (
            $universityPolicy?->students_frozen
            && (int) $universityPolicy->updated_by !== (int) $admin->id
        ) {
            $freezeOwner = $universityPolicy->updated_by
                ? User::find($universityPolicy->updated_by)
                : null;
            return response()->json([
                'message' => $freezeOwner
                    ? "Student access for the entire university was frozen by {$freezeOwner->email}. Restore university student access to change this student."
                    : 'Student access for the entire university is frozen. Restore university student access to change this student.',
                'freeze_owner_email' => $freezeOwner?->email,
            ], 403);
        }
        if ($user->access_frozen === true) {
            $freezeOwnerId = (int) $user->access_frozen_by;
            if ($freezeOwnerId !== (int) $admin->id) {
                $freezeOwner = $freezeOwnerId ? User::find($freezeOwnerId) : null;
                return response()->json([
                    'message' => $freezeOwner
                        ? "This student was frozen by {$freezeOwner->email}. Only that administrator can unfreeze this account."
                        : 'This student was frozen by another administrator. Only that administrator can unfreeze this account.',
                    'freeze_owner_email' => $freezeOwner?->email,
                ], 403);
            }
        }
        $user->forceFill([
            'access_frozen' => $frozen,
            'access_frozen_at' => $frozen ? now() : null,
            'access_frozen_by' => $frozen ? $admin->id : null,
        ])->save();
        if ($frozen) {
            $user->tokens()->delete();
        }

        $this->logAdminAction(
            $frozen ? 'froze_student_account' : 'unfroze_student_account',
            $user->email,
            $user->university_code,
            ['student_user_id' => $user->id, 'actor_email' => $admin->email],
        );

        return response()->json([
            'message' => $frozen ? 'Student account frozen.' : 'Student account access restored.',
            'is_frozen' => $user->isAccessFrozen(),
        ]);
    }

    public function deleteStudentAccount(Request $request, User $user)
    {
        $admin = $request->user();
        if ($admin->role !== 'admin' || !$admin->university_code || $this->isSuperAdmin($admin)) {
            return response()->json([
                'message' => 'Only a university subadmin can remove student accounts.',
            ], 403);
        }
        if (!in_array($user->role, ['student', 'user'], true)) {
            return response()->json([
                'message' => 'Only student accounts can be removed here.',
            ], 422);
        }
        if ($user->university_code !== $admin->university_code) {
            return response()->json([
                'message' => 'You may only remove student accounts from your university.',
            ], 403);
        }

        $targetEmail = $user->email;
        $universityCode = $user->university_code;
        $studentUserId = $user->id;
        $actorEmail = $admin->email;
        $deletedCertificates = DB::transaction(function () use (
            $user,
            $targetEmail,
            $universityCode,
            $actorEmail,
        ): int {
            $user->tokens()->delete();

            $certificateQuery = DB::table('certificates')
                ->where('university_code', $universityCode)
                ->where(function ($query) use ($targetEmail) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [
                        strtolower(trim($targetEmail)),
                    ])->orWhereRaw('LOWER(TRIM(email)) = ?', [
                        strtolower(trim($targetEmail)),
                    ]);
                });
            $certificates = $certificateQuery->get([
                'certificate_code',
                'cert_hash',
                'university_code',
            ]);
            $this->recordRevokedCredentialIdentifiers($certificates, $actorEmail);
            $deletedCertificates = $certificateQuery->delete();
            $user->delete();

            return $deletedCertificates;
        });

        $this->logAdminAction(
            'deleted_student_account',
            $targetEmail,
            $universityCode,
            [
                'student_user_id' => $studentUserId,
                'deleted_certificate_count' => $deletedCertificates,
            ],
        );

        return response()->json([
            'message' => 'Student account and issued database credentials were removed. Immutable blockchain transactions remain on-chain.',
            'data' => [
                'deleted_user_id' => $studentUserId,
                'university_code' => $universityCode,
                'deleted_certificate_count' => $deletedCertificates,
            ],
        ]);
    }

    public function purgeAccountsAndCredentials(Request $request)
    {
        $this->ensureSuperAdmin($request);
        $actor = $request->user();
        abort_unless($actor?->role === 'admin', 403);

        $deleted = DB::transaction(function () use ($actor): array {
            $accounts = User::query()
                ->whereIn('role', ['admin', 'student', 'user'])
                ->whereRaw('LOWER(TRIM(email)) != ?', ['certitrust256@gmail.com'])
                ->get(['id', 'email', 'role']);
            $accountIds = $accounts->pluck('id')->all();
            $subadminCount = $accounts->where('role', 'admin')->count();
            $studentCount = $accounts
                ->whereIn('role', ['student', 'user'])
                ->count();
            $accounts->each(fn (User $account) => $account->tokens()->delete());

            $certificateQuery = DB::table('certificates');
            $certificates = $certificateQuery->get([
                'certificate_code',
                'cert_hash',
                'university_code',
            ]);
            $this->recordRevokedCredentialIdentifiers($certificates, $actor->email);
            $certificateCount = $certificateQuery->delete();
            $accountCount = $accountIds === []
                ? 0
                : User::whereIn('id', $accountIds)->delete();

            return [
                'deleted_subadmin_count' => $subadminCount,
                'deleted_student_count' => $studentCount,
                'deleted_account_count' => $accountCount,
                'deleted_certificate_count' => $certificateCount,
            ];
        });

        $this->logAdminAction(
            'purged_all_accounts_and_credentials',
            null,
            null,
            $deleted + [
                'university_registrations_retained' => true,
                'super_admin_retained' => true,
                'blockchain_transactions_retained' => true,
            ],
        );

        return response()->json([
            'message' => 'All university subadmin and student/user accounts and database credentials were removed. Old credential QR codes are marked removed. The Super Admin, university registrations, and blockchain transactions remain.',
            'data' => $deleted,
        ]);
    }

    public function listDeletedSubadminUniversities(Request $request)
    {
        $this->ensureSuperAdmin($request);

        if (!Schema::hasTable('admin_action_logs')) {
            return response()->json(['data' => []]);
        }

        $deletions = AdminActionLog::query()
            ->where('action', 'deleted_subadmin')
            ->whereNotNull('university_code')
            ->latest('created_at')
            ->get(['id', 'target_email', 'university_code', 'created_at']);

        return response()->json([
            'data' => $deletions
                ->groupBy(fn (AdminActionLog $log) => strtoupper((string) $log->university_code))
                ->map(function ($logs, string $code) {
                    return [
                        'university_code' => $code,
                        'university_name' => University::find($code)?->university_name
                            ?: $this->universityDisplayName($code),
                        'deleted_subadmins' => $logs
                            ->map(fn (AdminActionLog $log) => [
                                'email' => $log->target_email,
                                'deleted_at' => $log->created_at?->toISOString(),
                            ])
                            ->values(),
                        'latest_deleted_at' => $logs->first()?->created_at?->toISOString(),
                    ];
                })
                ->values(),
        ]);
    }

    public function deleteJunkStudent(Request $request, string $universityCode, User $user)
    {
        $this->ensureSuperAdmin($request);
        $universityCode = strtoupper($universityCode);
        abort_unless(University::whereKey($universityCode)->exists(), 404);

        if (
            !in_array($user->role, ['student', 'user'], true)
            || strtoupper((string) $user->university_code) !== $universityCode
        ) {
            return response()->json([
                'message' => 'The selected account is not a student at this university.',
            ], 422);
        }

        $studentEmail = strtolower(trim((string) $user->email));
        $studentName = $user->name;
        $studentId = $user->id;
        $actorEmail = $request->user()?->email;

        $deletedCertificates = DB::transaction(function () use (
            $user,
            $studentEmail,
            $universityCode,
            $actorEmail,
        ): int {
            $user->tokens()->delete();
            $certificateQuery = DB::table('certificates')
                ->where('university_code', $universityCode)
                ->where(function ($query) use ($studentEmail) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$studentEmail])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [$studentEmail]);
                });
            $certificates = $certificateQuery->get([
                'certificate_code',
                'cert_hash',
                'university_code',
            ]);
            $this->recordRevokedCredentialIdentifiers($certificates, $actorEmail);
            $deletedCertificates = $certificateQuery->delete();
            $user->delete();

            return $deletedCertificates;
        });

        $this->logAdminAction(
            'purged_student_record',
            $studentEmail,
            $universityCode,
            [
                'student_user_id' => $studentId,
                'student_name' => $studentName,
                'deleted_certificate_count' => $deletedCertificates,
            ],
        );

        return response()->json([
            'message' => 'Student account and its database certificate records were permanently deleted.',
            'deleted_certificate_count' => $deletedCertificates,
        ]);
    }

    public function deleteJunkUniversityRecords(Request $request, string $universityCode)
    {
        $this->ensureSuperAdmin($request);
        $universityCode = strtoupper($universityCode);
        abort_unless(University::whereKey($universityCode)->exists(), 404);

        $actorEmail = $request->user()?->email;
        [$deletedStudents, $deletedCertificates] = DB::transaction(function () use ($universityCode, $actorEmail): array {
            $students = User::whereIn('role', ['student', 'user'])
                ->where('university_code', $universityCode)
                ->get();
            $students->each(fn (User $student) => $student->tokens()->delete());
            $certificateQuery = DB::table('certificates')
                ->where('university_code', $universityCode);
            $certificates = $certificateQuery->get([
                'certificate_code',
                'cert_hash',
                'university_code',
            ]);
            $this->recordRevokedCredentialIdentifiers($certificates, $actorEmail);
            $deletedCertificates = $certificateQuery->delete();
            $deletedStudents = User::whereIn('role', ['student', 'user'])
                ->where('university_code', $universityCode)
                ->delete();

            return [$deletedStudents, $deletedCertificates];
        });

        $this->logAdminAction(
            'purged_university_student_records',
            null,
            $universityCode,
            [
                'deleted_student_count' => $deletedStudents,
                'deleted_certificate_count' => $deletedCertificates,
                'university_registration_retained' => true,
            ],
        );

        return response()->json([
            'message' => 'All student accounts and database certificate records for this university were permanently deleted. University registration and immutable blockchain transactions were retained.',
            'deleted_student_count' => $deletedStudents,
            'deleted_certificate_count' => $deletedCertificates,
        ]);
    }

    public function updateAllStudentAccess(Request $request)
    {
        $admin = $request->user();
        if ($admin->role !== 'admin' || !$admin->university_code || $this->isSuperAdmin($admin)) {
            return response()->json([
                'message' => 'Only a university subadmin can manage student access.',
            ], 403);
        }

        $validated = $request->validate(['frozen' => ['required', 'boolean']]);
        $frozen = (bool) $validated['frozen'];
        $accessControl = UniversityAccessControl::where(
            'university_code',
            $admin->university_code,
        )->first();
        if (
            $accessControl?->students_frozen
            && (int) $accessControl->updated_by !== (int) $admin->id
        ) {
            return response()->json([
                'message' => $frozen
                    ? 'Student access is already frozen by another administrator.'
                    : 'Only the administrator who froze student access can restore it.',
            ], 403);
        }
        DB::transaction(function () use ($admin, $frozen): void {
            UniversityAccessControl::updateOrCreate(
                ['university_code' => $admin->university_code],
                ['students_frozen' => $frozen, 'updated_by' => $admin->id],
            );
            if ($frozen) {
                User::whereIn('role', ['student', 'user'])
                    ->where('university_code', $admin->university_code)
                    ->where('access_frozen', false)
                    ->update([
                        'access_frozen' => null,
                        'access_frozen_at' => null,
                        'access_frozen_by' => null,
                    ]);
                User::whereIn('role', ['student', 'user'])
                    ->where('university_code', $admin->university_code)
                    ->get()
                    ->each(fn (User $student) => $student->tokens()->delete());
            } else {
                User::whereIn('role', ['student', 'user'])
                    ->where('university_code', $admin->university_code)
                    ->where('access_frozen', true)
                    ->where('access_frozen_by', $admin->id)
                    ->update([
                        'access_frozen' => false,
                        'access_frozen_at' => null,
                        'access_frozen_by' => null,
                    ]);
            }
        });

        $this->logAdminAction(
            $frozen ? 'froze_all_students' : 'unfroze_all_students',
            null,
            $admin->university_code,
            ['frozen' => $frozen],
        );

        return response()->json([
            'message' => $frozen ? 'All student accounts are frozen.' : 'All student account restrictions have been cleared.',
            'university_students_frozen' => $frozen,
        ]);
    }

    public function bindSubadmin(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $validated = $request->validate([
            'university_code' => ['required', 'string', 'max:10', 'regex:/^[A-Z0-9]+$/'],
            'university_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'branch_campus' => ['nullable', 'string', 'max:255'],
            'display_name' => ['sometimes', 'nullable', 'string', 'max:30'],
            'email' => ['required', 'email'],
            'name' => ['nullable', 'string', 'max:255'],
        ]);

        $registeredUniversity = University::find($validated['university_code']);
        $universityName = trim($validated['university_name'] ?? $registeredUniversity?->university_name ?? '');
        $displayName = trim($validated['display_name'] ?? $registeredUniversity?->display_name ?? '');
        if ($universityName === '' || $displayName === '') {
            return response()->json([
                'message' => 'A university name and display name are required for a new university scope.',
            ], 422);
        }
        if (University::where('display_name', $displayName)
            ->whereKeyNot($validated['university_code'])
            ->exists()) {
            return response()->json([
                'message' => 'This university display name is already in use. Choose another short name.',
            ], 422);
        }

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

        University::updateOrCreate(
            ['code' => $validated['university_code']],
            [
                'university_name' => $universityName,
                'branch_campus' => array_key_exists('branch_campus', $validated)
                    ? (filled($validated['branch_campus'])
                        ? trim($validated['branch_campus'])
                        : null)
                    : $registeredUniversity?->branch_campus,
                'display_name' => $displayName,
            ],
        );

        if ($existingAdmin) {
            $previousEmail = $existingAdmin->email;
            $emailChanged = strtolower($previousEmail) !== $email;
            $existingAdmin->forceFill([
                'email' => $email,
                'name' => $validated['name'] ?? $existingAdmin->name ?? 'University Admin',
                'role' => 'admin',
                'university_code' => $validated['university_code'],
                'google_id' => $emailChanged ? null : $existingAdmin->google_id,
            ])->save();
            if ($emailChanged) {
                $existingAdmin->tokens()->delete();
            }

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
            'university_code' => ['sometimes', 'required', 'string', 'max:10', 'regex:/^[A-Z0-9]+$/', 'exists:universities,code'],
            'university_name' => ['sometimes', 'required', 'string', 'max:255'],
            'branch_campus' => ['sometimes', 'nullable', 'string', 'max:255'],
            'display_name' => ['sometimes', 'required', 'string', 'max:30'],
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

        $nextUniversityCode = $validated['university_code'] ?? $user->university_code;
        $anotherAdmin = User::where('role', 'admin')
            ->where('university_code', $nextUniversityCode)
            ->whereKeyNot($user->id)
            ->exists();
        if ($anotherAdmin) {
            return response()->json([
                'message' => 'This university already has a registered subadmin.',
            ], 422);
        }
        if (isset($validated['university_name'], $validated['display_name'])) {
            $duplicateDisplayName = University::where('display_name', $validated['display_name'])
                ->whereKeyNot($nextUniversityCode)
                ->exists();
            if ($duplicateDisplayName) {
                return response()->json([
                    'message' => 'This university display name is already in use. Choose another short name.',
                ], 422);
            }
            University::updateOrCreate(
                ['code' => $nextUniversityCode],
                [
                    'university_name' => trim($validated['university_name']),
                    'branch_campus' => filled($validated['branch_campus'] ?? null)
                        ? trim($validated['branch_campus'])
                        : null,
                    'display_name' => trim($validated['display_name']),
                ],
            );
        }

        $previousEmail = $user->email;
        $emailChanged = strtolower($previousEmail) !== $nextEmail;
        $user->fill([
            'email' => $nextEmail,
            'name' => $validated['name'] ?? $user->name,
            'university_code' => $validated['university_code'] ?? $user->university_code,
            'role' => 'admin',
        ]);
        if ($emailChanged) {
            $user->google_id = null;
        }

        $user->save();
        if ($emailChanged) {
            $user->tokens()->delete();
        }

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

        if ($user->role !== 'admin' || $this->isSuperAdmin($user) || !$user->university_code) {
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

        $universities = University::query()
            ->orderBy('university_name')
            ->get()
            ->map(fn (University $university) => [
                'code' => $university->code,
                'name' => $university->university_name,
                'display_name' => $university->display_name,
                'branch_campus' => $university->branch_campus,
            ])
            ->values();
        $credentialGroups = DB::table('certificates')
            ->selectRaw(
                "SUBSTR(CAST(issue_date AS TEXT), 1, 4) AS batch_year, university_code, COUNT(*) AS total_count, SUM(CASE WHEN LOWER(status) IN ('verified', 'valid') THEN 1 ELSE 0 END) AS verified_count",
            )
            ->groupByRaw('SUBSTR(CAST(issue_date AS TEXT), 1, 4), university_code')
            ->orderByDesc('batch_year')
            ->orderBy('university_code')
            ->get();
        $universitiesByCode = $universities->keyBy('code');
        $credentialBatches = $credentialGroups
            ->groupBy('batch_year')
            ->map(fn ($groups, $year) => [
                'batch_year' => (string) $year,
                'total_count' => (int) $groups->sum('total_count'),
                'verified_count' => (int) $groups->sum('verified_count'),
                'universities' => $groups->map(fn ($group) => [
                    'code' => $group->university_code,
                    'name' => $universitiesByCode->get($group->university_code)['name']
                        ?? $this->universityDisplayName($group->university_code),
                    'display_name' => $universitiesByCode->get($group->university_code)['display_name']
                        ?? $group->university_code,
                    'total_count' => (int) $group->total_count,
                    'verified_count' => (int) $group->verified_count,
                ])->values(),
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
                'verified_credentials' => DB::table('certificates')
                    ->whereIn(DB::raw('LOWER(status)'), ['verified', 'valid'])
                    ->count(),
                'credential_batches' => $credentialBatches,
                'pending_actions' => 0,
                'admins' => $admins,
                'activity' => $certificates,
                'history' => $history,
            ],
        ]);
    }

    private function isSuperAdmin(User $user): bool
    {
        return strtolower((string) $user->email) === 'certitrust256@gmail.com';
    }

    private function frozenLoginResponse(User $user, bool $hasCertificate)
    {
        $actor = User::find($user->accessFrozenById());
        $contact = $actor ? [
            'id' => $actor->id,
            'name' => $actor->name ?: ($this->isSuperAdmin($actor)
                ? 'CertiTrust Super Admin'
                : 'University administrator'),
            'role_label' => $this->isSuperAdmin($actor)
                ? 'CertiTrust Super Admin'
                : 'University subadmin',
            'university_code' => $actor->university_code,
        ] : null;

        return response()->json([
            'status' => 'frozen',
            'message' => $contact
                ? 'Your account was frozen by ' . $contact['name'] . '. You can use the support chat to contact them and resolve the issue.'
                : 'Your account is frozen. Contact your administrator to resolve the issue.',
            'token' => $user->createToken('CertiTrustFrozenSupportChat')->plainTextToken,
            'email' => $user->email,
            'role' => $user->role ?? 'student',
            'university_code' => $user->university_code,
            'has_certificate' => $hasCertificate,
            'access_frozen' => true,
            'freeze_contact' => $contact,
            'user' => $user->only(['id', 'name', 'email', 'role', 'university_code']),
        ]);
    }

    private function universityStudentsAreFrozen(string $universityCode): bool
    {
        return (bool) UniversityAccessControl::query()
            ->where('university_code', $universityCode)
            ->value('students_frozen');
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

    private function recordRevokedCredentialIdentifiers(iterable $certificates, ?string $actorEmail): void
    {
        if (!Schema::hasTable('revoked_credentials')) {
            abort(503, 'Credential removal tracking is unavailable. Apply the pending database migrations before removing accounts or credentials.');
        }

        $now = now();
        $revoked = [];
        foreach ($certificates as $certificate) {
            $revoked[] = [
                'certificate_code' => $certificate->certificate_code,
                'cert_hash' => $certificate->cert_hash,
                'university_code' => $certificate->university_code,
                'revoked_by_email' => $actorEmail,
                'revoked_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }
        if ($revoked !== []) {
            DB::table('revoked_credentials')->insert($revoked);
        }
    }

    private function universityDisplayName(?string $code): string
    {
        return University::find(strtoupper((string) $code))?->university_name
            ?: match (strtoupper((string) $code)) {
                'UCU' => 'Urdaneta City University',
                'PSU' => 'Pangasinan State University',
                default => $code ?: 'University',
            };
    }

    private function degreeType(?string $degree): string
    {
        $normalized = strtolower(trim((string) $degree));
        if (
            str_contains($normalized, 'master')
            || preg_match('/\b(mba|ma|maed|m\.ed|med|ms|msc|m\.sc|msit|m\.s|mpa|mph|mfa)\b/i', $normalized)
        ) {
            return 'Masteral';
        }
        if (
            str_contains($normalized, 'doctor')
            || preg_match('/\b(phd|ph\.d|edd|ed\.d)\b/i', $normalized)
        ) {
            return 'Doctoral';
        }
        if (
            str_contains($normalized, 'bachelor')
            || preg_match('/\b(bs[a-z]{0,4}|ba[a-z]{0,4}|bsc|bba|beed|bsed|bshm|bstm|bsn|bsa|b\.s|b\.a|b\.sba)\b/i', $normalized)
        ) {
            return 'Undergraduate';
        }

        return 'Other';
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
                            if ($this->hasVerifiedGoogleEmail($fallbackData)) {
                                return $fallbackData;
                            }
                        }

                        throw new \InvalidArgumentException('Google ID token audience does not match this application.');
                    }
                }

                if (!$this->hasVerifiedGoogleEmail($data)) {
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
        if (!$this->hasVerifiedGoogleEmail($data)) {
            throw new \InvalidArgumentException('Google account email could not be verified.');
        }

        return $data;
    }

    private function hasVerifiedGoogleEmail(array $data): bool
    {
        return !empty($data['email'])
            && filter_var($data['email_verified'] ?? false, FILTER_VALIDATE_BOOLEAN);
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
                    'message' => 'The Student ID is incorrect. Please check it and try again.',
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