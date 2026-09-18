use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Models\User; // or your User/Certificate mapping model

public function googleLogin(Request $request)
{
    $request->validate([
        'idToken' => 'required|string',
        'accessToken' => 'nullable|string',
    ]);

    $idToken = $request->input('idToken');
    $accessToken = $request->input('accessToken');
    $email = null;

    // Approach 1: Try decoding/verifying as a Google JWT ID Token (Mobile)
    try {
        $client = new \Google_Client(['client_id' => env('GOOGLE_CLIENT_ID')]);
        $payload = $client->verifyIdToken($idToken);
        if ($payload) {
            $email = $payload['email'];
        }
    } catch (\Exception $e) {
        // Not a valid JWT ID Token, might be an Access Token from web
    }

    // Approach 2: If $email is still null, treat $idToken (or $accessToken) as an Access Token and query Google UserInfo API (Web Fallback)
    if (!$email) {
        $tokenToVerify = $accessToken ?: $idToken;
        
        $response = Http::withToken($tokenToVerify)->get('https://www.googleapis.com/oauth2/v3/userinfo');

        if ($response->successful()) {
            $googleUser = $response->json();
            $email = $googleUser['email'] ?? null;
        }
    }

    if (!$email) {
        return response()->json([
            'message' => 'Invalid Google authentication token.'
        ], 401);
    }

    // Check your database for the user / certificate mapping
    // Example response structure expected by your Flutter app:
    return response()->json([
        'email' => $email,
        'role' => $email === 'certitrust256@gmail.com' ? 'admin' : 'student',
        'has_certificate' => true, // Check your certificates table here
    ]);
}