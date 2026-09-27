<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AdminActionLog extends Model
{
    protected $table = 'admin_action_logs';

    protected $fillable = [
        'actor_email',
        'action',
        'target_email',
        'university_code',
        'details',
    ];

    protected $casts = [
        'details' => 'array',
    ];
}
