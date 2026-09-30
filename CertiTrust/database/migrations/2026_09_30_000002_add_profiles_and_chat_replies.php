<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('profile_image_url')->nullable();
            $table->string('profile_icon', 20)->nullable();
        });

        Schema::table('chat_messages', function (Blueprint $table) {
            $table->foreignId('reply_to_id')->nullable()->constrained('chat_messages')->nullOnDelete();
            $table->boolean('is_report')->default(false)->index();
        });
    }

    public function down(): void
    {
        Schema::table('chat_messages', function (Blueprint $table) {
            $table->dropForeign(['reply_to_id']);
            $table->dropColumn(['reply_to_id', 'is_report']);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['profile_image_url', 'profile_icon']);
        });
    }
};