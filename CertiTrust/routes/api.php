<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CertificateController;
use App\Http\Controllers\CertificateDeletionRequestController;
use App\Http\Controllers\ChatController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "api" middleware group.
|
*/

// API Health / Root Route
Route::get('/', function () {
    return response()->json([
        'status' => 'ok',
        'message' => 'CertiTrust API is running.',
        'version' => '1.0.0',
        'endpoints' => [
            'login' => '/api/login',
            'google' => '/api/auth/google',
            'certificates' => '/api/certificates/{code}',
            'health' => '/api/health',
        ],
    ]);
});

Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'message' => 'Healthy',
    ]);
});

// Authentication Routes
Route::post('/login', [AuthController::class, 'login']);
Route::post('/auth/google', [AuthController::class, 'googleLogin']);

// Public verification is available by code; certificate lists require a school-scoped session.
Route::get('/certificates/{code}', [CertificateController::class, 'show']);

// Protected Routes (Requires Sanctum Token)
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', function (Request $request) {
        return $request->user();
    });
    Route::post('/user/profile', [AuthController::class, 'updateProfile']);

    Route::post('/admin/users', [AuthController::class, 'createAdmin']);
    Route::get('/admin/subadmins', [AuthController::class, 'listSubadmins']);
    Route::post('/admin/subadmins', [AuthController::class, 'bindSubadmin']);
    Route::put('/admin/subadmins/{user}', [AuthController::class, 'updateSubadmin']);
    Route::delete('/admin/subadmins/{user}/google', [AuthController::class, 'unbindSubadminGoogle']);
    Route::delete('/admin/subadmins/{user}', [AuthController::class, 'deleteSubadmin']);
    Route::get('/admin/history', [AuthController::class, 'adminActionHistory']);
    Route::get('/admin/overview', [AuthController::class, 'superAdminOverview']);

    Route::post('/auth/verify-student', [AuthController::class, 'verifyStudentId']);
    
    Route::post('/certificates', [CertificateController::class, 'store']);
    Route::post('/certificates/upload', [CertificateController::class, 'storeWithFile']);
    Route::post('/certificates/check-diploma-file-names', [CertificateController::class, 'checkDiplomaFileNames']);
    Route::post('/certificates/batch', [CertificateController::class, 'storeBatch']);
    Route::get('/certificates', [CertificateController::class, 'index']);
    Route::post('/certificates/{certificate}/deletion-request', [CertificateDeletionRequestController::class, 'store']);
    Route::get('/admin/certificate-deletion-requests', [CertificateDeletionRequestController::class, 'index']);
    Route::patch('/admin/certificate-deletion-requests/{deletionRequest}', [CertificateDeletionRequestController::class, 'review']);
    Route::get('/chat/messages', [ChatController::class, 'index']);
    Route::get('/chat/contacts', [ChatController::class, 'contacts']);
    Route::get('/chat/presence', [ChatController::class, 'presence']);
    Route::post('/chat/messages', [ChatController::class, 'store']);
    Route::delete('/chat/messages/{chatMessage}', [ChatController::class, 'destroy']);
    Route::delete('/chat/conversation/{userId}', [ChatController::class, 'clearConversation']);
    Route::post('/user/presence', function (Request $request) {
        $request->user()->forceFill(['last_seen_at' => now()])->save();
        return response()->json(['last_seen_at' => $request->user()->last_seen_at]);
    });
});