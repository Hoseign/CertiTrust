<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->string('diploma_file_name')->nullable()->after('diploma_url');
        });

        $usedFileNames = [];
        DB::table('certificates')
            ->whereNotNull('diploma_url')
            ->orderBy('id')
            ->get(['id', 'diploma_url'])
            ->each(function (object $certificate) use (&$usedFileNames): void {
                $value = (string) $certificate->diploma_url;
                $path = str_contains($value, '://')
                    ? (parse_url($value, PHP_URL_PATH) ?: $value)
                    : $value;
                $fileName = strtolower(trim(rawurldecode(basename(
                    str_replace('\\', '/', $path)
                ))));

                if ($fileName === '' || strlen($fileName) > 255 || isset($usedFileNames[$fileName])) {
                    return;
                }

                DB::table('certificates')
                    ->where('id', $certificate->id)
                    ->update(['diploma_file_name' => $fileName]);
                $usedFileNames[$fileName] = true;
            });

        Schema::table('certificates', function (Blueprint $table) {
            $table->unique('diploma_file_name', 'certificates_diploma_file_name_unique');
        });
    }

    public function down(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->dropUnique('certificates_diploma_file_name_unique');
            $table->dropColumn('diploma_file_name');
        });
    }
};
