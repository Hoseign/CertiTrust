<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "api" middleware group. Make sure everything matches!
|
*/

// Google Authentication Route
Route::post('/auth/google', [AuthController::class, 'googleLogin']);

// Student ID Verification Route
Route::post('/auth/verify-student-id', [AuthController::class, 'verifyStudentId']);