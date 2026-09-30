<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ChatMessage extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id', 'recipient_user_id', 'university_code', 'sender_email', 'sender_name', 'message', 'attachment_url', 'attachment_type', 'reply_to_id', 'is_report', 'deleted_by', 'deleted_for_everyone_at',
    ];

    protected $casts = [
        'deleted_by' => 'array',
        'deleted_for_everyone_at' => 'datetime',
        'is_report' => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function recipient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recipient_user_id');
    }

    public function replyTo(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reply_to_id');
    }
}