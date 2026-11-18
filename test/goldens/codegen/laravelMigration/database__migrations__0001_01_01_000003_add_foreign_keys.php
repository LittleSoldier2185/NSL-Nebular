<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->foreign('customer_id')->references('id')->on('customers')->onDelete('cascade')->onUpdate('no action');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropForeign(['customer_id']);
        });
    }
};
