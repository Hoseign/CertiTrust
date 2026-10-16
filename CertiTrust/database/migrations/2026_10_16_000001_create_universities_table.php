<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('universities', function (Blueprint $table) {
            $table->string('code', 10)->primary();
            $table->string('university_name');
            $table->string('branch_campus')->nullable();
            $table->string('display_name', 30)->unique();
            $table->timestamps();
        });

        $now = now();
        DB::table('universities')->insert([
            [
                'code' => 'UCU',
                'university_name' => 'Urdaneta City University',
                'branch_campus' => null,
                'display_name' => 'UCU',
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'code' => 'PSU',
                'university_name' => 'Pangasinan State University',
                'branch_campus' => null,
                'display_name' => 'PSU',
                'created_at' => $now,
                'updated_at' => $now,
            ],
        ]);

        $existingCodes = DB::table('users')
            ->whereNotNull('university_code')
            ->where('university_code', '!=', '')
            ->distinct()
            ->pluck('university_code')
            ->merge(
                DB::table('certificates')
                    ->whereNotNull('university_code')
                    ->where('university_code', '!=', '')
                    ->distinct()
                    ->pluck('university_code'),
            )
            ->map(fn ($code) => strtoupper((string) $code))
            ->unique()
            ->reject(fn ($code) => DB::table('universities')->where('code', $code)->exists());

        foreach ($existingCodes as $code) {
            $normalizedCode = strtoupper((string) $code);
            if (preg_match('/^[A-Z0-9]{1,10}$/', $normalizedCode) !== 1) {
                continue;
            }
            DB::table('universities')->insert([
                'code' => $normalizedCode,
                'university_name' => $normalizedCode,
                'branch_campus' => null,
                'display_name' => $normalizedCode,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('universities');
    }
};
