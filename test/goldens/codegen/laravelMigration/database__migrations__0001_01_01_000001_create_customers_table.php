<?php

// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customers', function (Blueprint $table) {
            $table->id();
            $table->string('email', 120)->unique();
            $table->timestamp('created_at')->nullable()->useCurrent();
            $table->comment('ลูกค้า');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customers');
    }
};
