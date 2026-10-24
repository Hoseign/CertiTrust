<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('revoked_credentials', function (Blueprint $table) {
            $table->id();
            $table->string('certificate_code')->nullable()->index();
            $table->string('cert_hash', 64)->nullable()->index();
            $table->string('university_code')->nullable()->index();
            $table->string('revoked_by_email')->nullable();
            $table->timestamp('revoked_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('revoked_credentials');
    }
};
