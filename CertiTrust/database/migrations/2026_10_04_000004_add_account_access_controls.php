<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('access_frozen')->nullable()->after('role');
            $table->timestamp('access_frozen_at')->nullable()->after('access_frozen');
            $table->unsignedBigInteger('access_frozen_by')->nullable()->after('access_frozen_at');
        });

        Schema::create('university_access_controls', function (Blueprint $table) {
            $table->id();
            $table->string('university_code')->unique();
            $table->boolean('students_frozen')->default(false);
            $table->unsignedBigInteger('updated_by')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('university_access_controls');

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'access_frozen',
                'access_frozen_at',
                'access_frozen_by',
            ]);
        });
    }
};
