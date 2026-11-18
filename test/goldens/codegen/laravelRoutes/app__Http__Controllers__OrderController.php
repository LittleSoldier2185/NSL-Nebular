<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OrderController extends Controller
{
    /** GET /orders — List orders */
    public function index(Request $request): JsonResponse
    {
        // TODO: ทำงานจริง
        return response()->json([], 200);
    }

    /** POST /orders — Create orders */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'customer_id' => 'required|integer',
            'status' => 'sometimes|string',
            'total' => 'sometimes|numeric',
        ]);
        // TODO: ทำงานจริง
        return response()->json([], 201);
    }

    /** GET /orders/{id} — Get orders */
    public function show(Request $request, string $id): JsonResponse
    {
        // TODO: ทำงานจริง
        return response()->json([], 200);
    }

    /** PATCH /orders/{id} — Update orders */
    public function update(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'customer_id' => 'sometimes|integer',
            'status' => 'sometimes|string',
            'total' => 'sometimes|numeric',
        ]);
        // TODO: ทำงานจริง
        return response()->json([], 200);
    }

    /** DELETE /orders/{id} — Delete orders */
    public function destroy(Request $request, string $id): JsonResponse
    {
        // TODO: ทำงานจริง
        return response()->json([], 204);
    }

}
