<?php

namespace App\Http\Controllers;

use App\Models\Certificate;
use App\Models\CertificateDeletionRequest;
use App\Models\ChatMessage;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CertificateDeletionRequestController extends Controller
{
    public function store(Request $request, int $certificateId)
    {
        $user = $request->user();
        if ($user->role !== 'admin' || !$user->university_code || $this->isSuperAdmin($user->email)) {
            return response()->json(['message' => 'Only a school subadmin can request credential deletion.'], 403);
        }

        $validated = $request->validate([
            'reason' => ['nullable', 'string', 'max:2000'],
        ]);

        $certificate = Certificate::whereKey($certificateId)
            ->where('university_code', $user->university_code)
            ->first();
        if (!$certificate) {
            return response()->json(['message' => 'The credential was not found in your school records.'], 404);
        }

        $alreadyPending = CertificateDeletionRequest::where('certificate_id', $certificate->id)
            ->where('status', 'pending')
            ->exists();
        if ($alreadyPending) {
            return response()->json(['message' => 'A deletion request for this credential is already pending.'], 422);
        }

        $deletionRequest = CertificateDeletionRequest::create([
            'certificate_id' => $certificate->id,
            'requested_by' => $user->id,
            'student_id' => $certificate->student_id,
            'student_name' => $certificate->student_name ?: $certificate->recipient_name,
            'student_email' => $certificate->student_email ?: $certificate->email,
            'degree' => $certificate->degree ?: $certificate->course_or_event,
            'university_code' => $certificate->university_code,
            'certificate_code' => $certificate->certificate_code,
            'cert_hash' => $certificate->cert_hash,
            'reason' => $validated['reason'] ?? null,
            'status' => 'pending',
        ]);

        return response()->json(['data' => $deletionRequest], 201);
    }

    public function index(Request $request)
    {
        if (!$this->isSuperAdmin($request->user()?->email)) {
            return response()->json(['message' => 'Only the Super Admin can review credential deletion requests.'], 403);
        }

        return response()->json([
            'data' => CertificateDeletionRequest::latest()->get()->map(function (CertificateDeletionRequest $item) {
                $item->requester_name = User::find($item->requested_by)?->name;
                $item->requester_email = User::find($item->requested_by)?->email;
                return $item;
            }),
        ]);
    }

    public function review(Request $request, int $deletionRequestId)
    {
        $reviewer = $request->user();
        if (!$this->isSuperAdmin($reviewer?->email)) {
            return response()->json(['message' => 'Only the Super Admin can review credential deletion requests.'], 403);
        }

        $validated = $request->validate([
            'decision' => ['required', 'in:approved,rejected'],
            'reviewer_note' => ['nullable', 'string', 'max:2000'],
        ]);

        return DB::transaction(function () use ($validated, $reviewer, $deletionRequestId) {
            $deletionRequest = CertificateDeletionRequest::lockForUpdate()->find($deletionRequestId);
            if (!$deletionRequest) {
                return response()->json(['message' => 'Deletion request not found.'], 404);
            }
            if ($deletionRequest->status !== 'pending') {
                return response()->json(['message' => 'This deletion request has already been reviewed.'], 422);
            }

            if ($validated['decision'] === 'approved') {
                $certificate = Certificate::lockForUpdate()->find($deletionRequest->certificate_id);
                if (!$certificate) {
                    return response()->json(['message' => 'The credential no longer exists.'], 404);
                }
                $certificate->delete();
            }

            $deletionRequest->forceFill([
                'status' => $validated['decision'],
                'reviewed_by' => $reviewer->id,
                'reviewer_note' => $validated['reviewer_note'] ?? null,
                'reviewed_at' => now(),
            ])->save();

            $requester = User::find($deletionRequest->requested_by);
            if ($requester) {
                $decisionLabel = $validated['decision'] === 'approved'
                    ? 'approved. The credential has been deleted.'
                    : 'rejected. The credential remains active.';
                $message = 'Deletion request for ' . $deletionRequest->student_name
                    . ' (Student ID ' . ($deletionRequest->student_id ?: 'N/A') . ') was '
                    . $decisionLabel;
                if (!empty($validated['reviewer_note'])) {
                    $message .= ' Super Admin note: ' . trim($validated['reviewer_note']);
                }

                ChatMessage::create([
                    'user_id' => $reviewer->id,
                    'recipient_user_id' => $requester->id,
                    'university_code' => $deletionRequest->university_code,
                    'sender_email' => $reviewer->email,
                    'sender_name' => 'CertiTrust Super Admin',
                    'message' => $message,
                    'deleted_by' => [],
                ]);
            }

            return response()->json(['data' => $deletionRequest->fresh()]);
        });
    }

    private function isSuperAdmin(?string $email): bool
    {
        return strtolower(trim((string) $email)) === 'certitrust256@gmail.com';
    }
}