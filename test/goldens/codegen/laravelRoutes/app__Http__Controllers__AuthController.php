<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuthController extends Controller
{
    /** POST /auth/login */
    public function login(Request $request): JsonResponse
    {
        // TODO: ทำงานจริง
        return response()->json([], 201);
    }

}
