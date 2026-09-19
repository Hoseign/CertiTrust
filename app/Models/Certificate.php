<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Certificate extends Model
{
    use HasFactory;

    protected $fillable = [
        'certificate_code',
        'student_id',
        'student_name',
        'recipient_name',
        'degree',
        'course_or_event',
        'university_code',
        'issue_date',
        'student_email',
        'diploma_url',
        'cert_hash',
        'status',
    ];
}