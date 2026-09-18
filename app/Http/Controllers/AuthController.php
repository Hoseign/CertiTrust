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
            $hasCertificate = DB::table('certificates')->where('email', $user->email)->exists();
            $role = $user->role ?? 'student';

            // Generate Sanctum token
            $token = $user->createToken('CertiTrustMobileToken')->plainTextToken;

            return response()->json([
                'status' => 'success',
                'message' => 'Successfully logged in.',
                'token' => $token,
                'email' => $user->email,
                'role' => $role,
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
                'id_token' => 'required|string',
                'access_token' => 'nullable|string',
            ]);

            $email = $request->input('email');
            $name = $request->input('name');
            $googleId = $request->input('google_id');

            // 1. If email wasn't passed directly, fetch profile from Google using the access_token
            if (!$email && $request->filled('access_token')) {
                // Added withoutVerifying() to fix local SSL certificate check errors (cURL error 60)
                $googleResponse = Http::withoutVerifying()
                    ->withToken($request->access_token)
                    ->get('https://www.googleapis.com/oauth2/v3/userinfo');

                if ($googleResponse->successful()) {
                    $googleData = $googleResponse->json();
                    $email = $googleData['email'] ?? null;
                    $name = $googleData['name'] ?? 'Google User';
                    $googleId = $googleData['sub'] ?? null;
                }
            }

            // 2. Fallback: Parse the JWT id_token payload if email is still missing
            if (!$email && $request->filled('id_token')) {
                $tokenParts = explode('.', $request->id_token);
                if (count($tokenParts) >= 2) {
                    $payload = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $tokenParts[1])), true);
                    $email = $payload['email'] ?? null;
                    $name = $payload['name'] ?? 'Google User';
                    $googleId = $payload['sub'] ?? null;
                }
            }

            if (!$email) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Email could not be resolved from the authentication payload.',
                ], 422);
            }

            $googleId = $googleId ?? ('google_' . md5($email));

            // Find or create the user based on Google email
            $user = User::firstOrCreate(
                ['email' => $email],
                [
                    'name' => $name ?? 'Google User',
                    'google_id' => $googleId,
                    'password' => Hash::make(Str::random(24)), // Random secure password for social logins
                ]
            );

            // If user exists but google_id wasn't set, update it
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

            // Query certificates table to verify the mapping between email and student ID
            $certificate = DB::table('certificates')
                ->where('email', $request->email)
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