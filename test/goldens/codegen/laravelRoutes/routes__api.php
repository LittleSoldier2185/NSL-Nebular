<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\OrderController;
use App\Http\Controllers\AuthController;

Route::get('/orders', [OrderController::class, 'index']);
Route::post('/orders', [OrderController::class, 'store'])->middleware('auth:sanctum');
Route::get('/orders/{id}', [OrderController::class, 'show']);
Route::patch('/orders/{id}', [OrderController::class, 'update']);
Route::delete('/orders/{id}', [OrderController::class, 'destroy']);
Route::post('/auth/login', [AuthController::class, 'login']);
