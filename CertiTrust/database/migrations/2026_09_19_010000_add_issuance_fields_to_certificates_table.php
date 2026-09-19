<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->string('student_name')->nullable();
            $table->string('degree')->nullable();
            $table->string('student_email')->nullable()->index();
            $table->text('diploma_url')->nullable();
            $table->string('cert_hash', 64)->nullable()->unique();
        });
    }

    public function down(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->dropUnique(['cert_hash']);
            $table->dropColumn(['student_name', 'degree', 'student_email', 'diploma_url', 'cert_hash']);
        });
    }
};
