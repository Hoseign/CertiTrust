<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('certificate_verifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('certificate_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->index(['created_at', 'certificate_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('certificate_verifications');
    }
};
