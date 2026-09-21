<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CertificateController;
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

    Route::post('/admin/users', [AuthController::class, 'createAdmin']);

    Route::post('/auth/verify-student', [AuthController::class, 'verifyStudentId']);
    
    Route::post('/certificates', [CertificateController::class, 'store']);
    Route::post('/certificates/upload', [CertificateController::class, 'storeWithFile']);
    Route::post('/certificates/batch', [CertificateController::class, 'storeBatch']);
    Route::get('/certificates', [CertificateController::class, 'index']);
    Route::get('/chat/messages', [ChatController::class, 'index']);
    Route::get('/chat/contacts', [ChatController::class, 'contacts']);
    Route::get('/chat/presence', [ChatController::class, 'presence']);
    Route::post('/chat/messages', [ChatController::class, 'store']);
    Route::post('/user/presence', function (Request $request) {
        $request->user()->forceFill(['last_seen_at' => now()])->save();
        return response()->json(['last_seen_at' => $request->user()->last_seen_at]);
    });
});