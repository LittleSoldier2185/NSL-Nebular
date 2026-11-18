<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->bigInteger('customer_id');
            $table->string('status', 20)->default('pending')->comment('สถานะ');
            $table->decimal('total', 10, 2)->nullable();
            $table->index(['status'], 'idx_orders_status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('orders');
    }
};
