<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chat_messages', function (Blueprint $table) {
            $table->json('deleted_by')->nullable()->after('attachment_type');
            $table->timestamp('deleted_for_everyone_at')->nullable()->after('deleted_by');
        });
    }

    public function down(): void
    {
        Schema::table('chat_messages', function (Blueprint $table) {
            $table->dropColumn(['deleted_by', 'deleted_for_everyone_at']);
        });
    }
};
