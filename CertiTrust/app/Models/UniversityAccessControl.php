<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UniversityAccessControl extends Model
{
    protected $fillable = [
        'university_code',
        'students_frozen',
        'updated_by',
    ];

    protected function casts(): array
    {
        return [
            'students_frozen' => 'boolean',
        ];
    }
}
