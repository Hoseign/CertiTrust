<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use App\Models\User;

class CertificateController extends Controller
{
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

            // Find or create the user based on Google email
            $user = User::firstOrCreate(
                ['email' => $email],
                [
                    'name' => $name,
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
}