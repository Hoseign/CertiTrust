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

// Google Authentication Route
Route::post('/auth/google', [AuthController::class, 'googleLogin']);

// Student ID Verification Route (Aligned with Flutter ApiService)
Route::post('/auth/verify-student', [AuthController::class, 'verifyStudentId']);

// Certificate Routes
Route::get('/certificates', [CertificateController::class, 'index']);
Route::get('/certificates/{code}', [CertificateController::class, 'show']);
Route::post('/certificates', [CertificateController::class, 'store']);
Route::post('/certificates/upload', [CertificateController::class, 'storeWithFile']);
Route::post('/certificates/batch', [CertificateController::class, 'storeBatch']);