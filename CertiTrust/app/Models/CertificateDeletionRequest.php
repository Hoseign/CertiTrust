<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CertificateDeletionRequest extends Model
{
    protected $fillable = [
        'certificate_id',
        'requested_by',
        'reviewed_by',
        'student_id',
        'student_name',
        'student_email',
        'degree',
        'university_code',
        'certificate_code',
        'cert_hash',
        'reason',
        'reviewer_note',
        'status',
        'reviewed_at',
    ];

    protected function casts(): array
    {
        return ['reviewed_at' => 'datetime'];
    }
}