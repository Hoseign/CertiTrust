<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->dropUnique('certificates_diploma_file_name_unique');
            $table->unsignedSmallInteger('degree_number')->nullable()->after('degree');
            $table->unique(
                ['university_code', 'diploma_file_name'],
                'certificates_university_diploma_file_name_unique',
            );
        });

        $degreeNumbers = [];
        \Illuminate\Support\Facades\DB::table('certificates')
            ->orderBy('issue_date')
            ->orderBy('id')
            ->get(['id', 'student_id', 'university_code'])
            ->each(function (object $certificate) use (&$degreeNumbers): void {
                $studentKey = strtolower(trim((string) $certificate->university_code))
                    . ':' . strtolower(trim((string) $certificate->student_id));
                $degreeNumbers[$studentKey] = ($degreeNumbers[$studentKey] ?? 0) + 1;
                \Illuminate\Support\Facades\DB::table('certificates')
                    ->where('id', $certificate->id)
                    ->update(['degree_number' => $degreeNumbers[$studentKey]]);
            });
    }

    public function down(): void
    {
        Schema::table('certificates', function (Blueprint $table) {
            $table->dropUnique('certificates_university_diploma_file_name_unique');
            $table->unique('diploma_file_name', 'certificates_diploma_file_name_unique');
            $table->dropColumn('degree_number');
        });
    }
};
