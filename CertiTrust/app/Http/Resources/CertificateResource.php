<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CertificateResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'certificate_code' => $this->certificate_code,
            'recipient_name' => $this->recipient_name,
            'course_or_event' => $this->course_or_event ?? $this->course_title ?? null,
            'university_code' => $this->university_code ?? null,
            'issue_date' => $this->issue_date,
            'status' => $this->status ?? 'valid',
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}