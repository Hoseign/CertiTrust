<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CertificateController;

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

// Public Certificate Routes
Route::get('/certificates', [CertificateController::class, 'index']);
Route::get('/certificates/{code}', [CertificateController::class, 'show']);

// Protected Routes (Requires Sanctum Token)
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', function (Request $request) {
        return $request->user();
    });

    Route::post('/auth/verify-student', [AuthController::class, 'verifyStudentId']);
    
    Route::post('/certificates', [CertificateController::class, 'store']);
    Route::post('/certificates/upload', [CertificateController::class, 'storeWithFile']);
    Route::post('/certificates/batch', [CertificateController::class, 'storeBatch']);
});