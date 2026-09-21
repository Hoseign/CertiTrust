<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    private function universityForEmail(string $email): ?string
    {
        return match (strtolower($email)) {
            'certitrust256@gmail.com' => 'UCU',
            'randygonzales2024@gmail.com' => 'PSU',
            default => null,
        };
    }

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

            $adminUniversity = $this->universityForEmail($email);
            $existingUser = User::where('email', $email)->first();
            $certificateQuery = DB::table('certificates')
                ->where(function ($query) use ($email) {
                    $query->where('email', $email)->orWhere('student_email', $email);
                });
            $hasCertificate = $certificateQuery->exists();
            if ($adminUniversity === null && $existingUser?->role !== 'admin' && !$hasCertificate) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'This Google account is not registered to an issued credential.',
                ], 403);
            }

            // Find or create the user based on Google email
            $user = User::firstOrCreate(
                ['email' => $email],
                [
                    'name' => $name ?? 'Google User',
                    'google_id' => $googleId,
                    'password' => Hash::make(Str::random(24)), // Random secure password for social logins
                ]
            );

            $adminUniversity = $this->universityForEmail($email);
            if ($adminUniversity !== null && ($user->role !== 'admin' || $user->university_code !== $adminUniversity)) {
                $user->forceFill(['role' => 'admin', 'university_code' => $adminUniversity])->save();
            }

            // If user exists but google_id wasn't set, update it
            if (!$user->google_id) {
                $user->update(['google_id' => $googleId]);
            }

            $role = $user->role ?? 'student';
            if ($adminUniversity === null && !$user->university_code) {
                $user->forceFill(['university_code' => $certificateQuery->value('university_code')])->save();
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
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'unique:users,email'],
            'university_code' => ['required', 'in:UCU,PSU'],
        ]);

        $admin = User::create([
            'name' => $validated['name'],
            'email' => strtolower($validated['email']),
            'password' => Hash::make(Str::random(32)),
            'role' => 'admin',
            'university_code' => $validated['university_code'],
        ]);

        return response()->json([
            'message' => 'Administrator account created successfully.',
            'admin' => $admin->only(['id', 'name', 'email', 'role', 'university_code']),
        ], 201);
    }

    /**
     * Validate the credential with Google and return its verified profile.
     */
    private function resolveGoogleUser(Request $request): array
    {
        if ($request->filled('id_token')) {
            $response = $this->googleHttp()->get('https://oauth2.googleapis.com/tokeninfo', [
                'id_token' => $request->string('id_token')->toString(),
            ]);

            if (!$response->successful()) {
                throw new \InvalidArgumentException('Google ID token is invalid or expired.');
            }

            $data = $response->json();
            $expectedClientId = (string) env('GOOGLE_CLIENT_ID');
            if ($expectedClientId === '' || ($data['aud'] ?? null) !== $expectedClientId) {
                throw new \InvalidArgumentException('Google ID token audience does not match this application.');
            }

            if (($data['email_verified'] ?? 'false') !== 'true') {
                throw new \InvalidArgumentException('Google email address is not verified.');
            }

            return $data;
        }

        $response = $this->googleHttp()
            ->withToken($request->string('access_token')->toString())
            ->get('https://www.googleapis.com/oauth2/v3/userinfo');

        if (!$response->successful()) {
            throw new \InvalidArgumentException('Google access token is invalid or expired.');
        }

        $data = $response->json();
        if (empty($data['email']) || ($data['email_verified'] ?? false) !== true) {
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

            if ($request->user()->email !== $request->input('email')) {
                return response()->json([
                    'success' => false,
                    'message' => 'The authenticated account does not match this email address.',
                ], 403);
            }

            // Query certificates table to verify the mapping between email and student ID
            $certificate = DB::table('certificates')
                ->where(function ($query) use ($request) {
                    $query->where('email', $request->email)
                        ->orWhere('student_email', $request->email);
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
}