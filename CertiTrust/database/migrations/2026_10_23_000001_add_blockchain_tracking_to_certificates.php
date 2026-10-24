<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->string('blockchain_status')->default('not_configured');
            $table->string('blockchain_tx_hash')->nullable()->index();
            $table->string('blockchain_network')->nullable();
            $table->text('blockchain_error')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->dropIndex(['blockchain_tx_hash']);
            $table->dropColumn([
                'blockchain_status',
                'blockchain_tx_hash',
                'blockchain_network',
                'blockchain_error',
            ]);
        });
    }
};