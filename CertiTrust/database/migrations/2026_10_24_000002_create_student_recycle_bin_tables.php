<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('student_deletion_requests', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('student_user_id')->index();
            $table->unsignedBigInteger('requested_by')->nullable()->index();
            $table->string('student_name');
            $table->string('student_email')->index();
            $table->string('university_code')->index();
            $table->text('reason')->nullable();
            $table->string('status')->default('pending')->index();
            $table->unsignedBigInteger('reviewed_by')->nullable();
            $table->text('reviewer_note')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();
        });

        Schema::create('junk_items', function (Blueprint $table) {
            $table->id();
            $table->string('record_type')->index();
            $table->string('university_code')->nullable()->index();
            $table->unsignedBigInteger('student_user_id')->nullable()->index();
            $table->string('student_name')->nullable();
            $table->string('student_email')->nullable()->index();
            $table->string('student_id')->nullable()->index();
            $table->string('source')->index();
            $table->string('deleted_by_email')->nullable();
            $table->longText('payload');
            $table->timestamp('deleted_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('junk_items');
        Schema::dropIfExists('student_deletion_requests');
    }
};
