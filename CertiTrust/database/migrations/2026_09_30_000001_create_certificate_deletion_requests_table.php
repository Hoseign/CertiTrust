<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('certificate_deletion_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('certificate_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('requested_by')->constrained('users')->cascadeOnDelete();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('student_id')->nullable();
            $table->string('student_name');
            $table->string('student_email')->nullable();
            $table->string('degree')->nullable();
            $table->string('university_code', 10)->index();
            $table->string('certificate_code')->nullable();
            $table->string('cert_hash', 64)->nullable();
            $table->text('reason')->nullable();
            $table->text('reviewer_note')->nullable();
            $table->string('status')->default('pending')->index();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('certificate_deletion_requests');
    }
};