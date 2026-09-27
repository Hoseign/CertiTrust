<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('chat_messages')) {
            return;
        }

        Schema::table('chat_messages', function (Blueprint $table) {
            if (!Schema::hasColumn('chat_messages', 'deleted_by')) {
                $table->json('deleted_by')->nullable()->after('attachment_type');
            }

            if (!Schema::hasColumn('chat_messages', 'deleted_for_everyone_at')) {
                $table->timestamp('deleted_for_everyone_at')->nullable()->after('deleted_by');
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('chat_messages')) {
            return;
        }

        Schema::table('chat_messages', function (Blueprint $table) {
            if (Schema::hasColumn('chat_messages', 'deleted_by')) {
                $table->dropColumn('deleted_by');
            }

            if (Schema::hasColumn('chat_messages', 'deleted_for_everyone_at')) {
                $table->dropColumn('deleted_for_everyone_at');
            }
        });
    }
};
