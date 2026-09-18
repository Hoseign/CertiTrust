<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Certificate extends Model
{
    use HasFactory;

    protected $fillable = [
        'certificate_code',
        'recipient_name',
        'course_or_event',
        'university_code',
        'issue_date',
        'status',
    ];
}