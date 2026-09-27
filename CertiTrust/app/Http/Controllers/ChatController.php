<?php

namespace App\Http\Controllers;

use App\Models\ChatMessage;
use App\Models\Certificate;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Carbon;

class ChatController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        $query = ChatMessage::query()
            ->where('university_code', $user->university_code)
            ->orderBy('created_at');
        if ($user->role === 'admin') {
            $targetId = $request->integer('student_id');
            if (!$targetId) {
                return response()->json(['data' => []]);
            }
            $query->where(function ($messages) use ($user, $targetId) {
                $messages->where(function ($thread) use ($user, $targetId) {
                    $thread->where('user_id', $user->id)->where('recipient_user_id', $targetId);
                })->orWhere(function ($thread) use ($user, $targetId) {
                    $thread->where('user_id', $targetId)->where('recipient_user_id', $user->id);
                });
            });
        } else {
            $query->where(function ($messages) use ($user) {
                $messages->where('user_id', $user->id)->orWhere('recipient_user_id', $user->id);
            });
        }

        $visibleMessages = $query->get()->filter(function (ChatMessage $message) use ($user) {
            if ($message->deleted_for_everyone_at) {
                return false;
            }

            $deletedBy = is_array($message->deleted_by) ? $message->deleted_by : [];
            return !in_array((int) $user->id, $deletedBy, true);
        })->values();

        return response()->json(['data' => $visibleMessages]);
    }

    public function contacts(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        if ($user->role !== 'admin') {
            return response()->json(['data' => []]);
        }

        $search = trim((string) $request->query('search', ''));
        $certificates = Certificate::where('university_code', $user->university_code);
        if ($search !== '') {
            $certificates->where(function ($query) use ($search) {
                $query->where('student_name', 'ilike', "%{$search}%")
                    ->orWhere('student_email', 'ilike', "%{$search}%")
                    ->orWhere('student_id', 'ilike', "%{$search}%")
                    ->orWhere('degree', 'ilike', "%{$search}%")
                    ->orWhere('certificate_code', 'ilike', "%{$search}%")
                    ->orWhere('cert_hash', 'ilike', "%{$search}%");
            });
        }

        $contacts = $certificates->get()->map(function (Certificate $certificate) {
            $studentEmail = $certificate->student_email ?: $certificate->email;
            $user = User::where('email', $studentEmail)->first();
            $lastSeen = $user?->last_seen_at;
            return [
                'id' => $user?->id,
                'name' => $user?->name ?? $certificate->student_name,
                'email' => $studentEmail,
                'student_id' => $certificate->student_id,
                'degree' => $certificate->degree,
                'certificate_code' => $certificate->certificate_code,
                'matched_field' => null,
                'is_active' => $lastSeen?->greaterThan(now()->subMinutes(5)) ?? false,
                'last_seen_label' => $lastSeen ? 'Last active: ' . $lastSeen->diffForHumans() : 'Last active: never',
                'university_code' => $certificate->university_code,
                'student_email' => $studentEmail,
            ];
        })->filter(fn (array $contact) => $contact['id'] !== null)->unique('id')->values();

        if ($search !== '') {
            $contacts = $contacts->map(function (array $contact) use ($search) {
                foreach (['name', 'student_id', 'email', 'degree', 'certificate_code'] as $field) {
                    if (str_contains(strtolower((string) ($contact[$field] ?? '')), strtolower($search))) {
                        $contact['matched_field'] = $field;
                        break;
                    }
                }
                return $contact;
            });
        }

        return response()->json(['data' => $contacts]);
    }

    public function presence(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        if ($user->role === 'admin') {
            $targets = User::where('university_code', $user->university_code)
                ->where('role', '!=', 'admin')
                ->get(['id', 'name', 'email', 'last_seen_at', 'university_code']);
        } else {
            $targets = User::where('university_code', $user->university_code)
                ->where('role', 'admin')
                ->get(['id', 'name', 'email', 'last_seen_at', 'university_code']);
        }

        return response()->json(['data' => $targets->map(fn (User $target) => [
            'id' => $target->id,
            'name' => $target->name,
            'email' => $target->email,
            'university_code' => $target->university_code,
            'is_active' => $target->last_seen_at?->greaterThan(now()->subMinutes(5)) ?? false,
            'last_seen_label' => $target->last_seen_at ? 'Last active: ' . $target->last_seen_at->diffForHumans() : 'Last active: never',
        ])]);
    }

    public function store(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        $validated = $request->validate([
            'message' => ['nullable', 'string', 'max:2000'],
            'recipient_user_id' => ['nullable', 'integer', 'exists:users,id'],
            'attachment' => ['nullable', 'file', 'mimes:jpg,jpeg,png,gif,mp4,mov,webm', 'max:51200'],
        ]);

        if (!$user->university_code) {
            return response()->json(['message' => 'Your account is not assigned to a school.'], 403);
        }

        $recipientId = $validated['recipient_user_id'] ?? null;
        if ($user->role === 'admin') {
            $recipient = User::whereKey($recipientId)->where('university_code', $user->university_code)->where('role', '!=', 'admin')->first();
            if (!$recipient) return response()->json(['message' => 'Select a student from your school.'], 422);
            $recipientId = $recipient->id;
        } else {
            $recipientId = User::where('university_code', $user->university_code)->where('role', 'admin')->value('id');
        }
        if (empty($validated['message']) && !$request->hasFile('attachment')) {
            return response()->json(['message' => 'Message or attachment is required.'], 422);
        }
        $attachmentUrl = null;
        $attachmentType = null;
        if ($request->hasFile('attachment')) {
            $file = $request->file('attachment');
            $attachmentUrl = Storage::disk('public')->url($file->store('chat', 'public'));
            $attachmentType = str_starts_with($file->getMimeType() ?? '', 'video/') ? 'video' : 'image';
        }

        $message = ChatMessage::create([
            'user_id' => $user->id,
            'recipient_user_id' => $recipientId,
            'university_code' => $user->university_code,
            'sender_email' => $user->email,
            'sender_name' => $user->name,
            'message' => $validated['message'] ?? '',
            'attachment_url' => $attachmentUrl,
            'attachment_type' => $attachmentType,
            'deleted_by' => [],
        ]);

        return response()->json(['data' => $message], 201);
    }

    public function destroy(Request $request, ChatMessage $chatMessage)
    {
        $user = $request->user();
        $mode = $request->query('mode', 'me');

        if ($chatMessage->user_id !== $user->id && $chatMessage->recipient_user_id !== $user->id && $user->role !== 'admin') {
            return response()->json(['message' => 'This message is not in your conversation.'], 403);
        }

        if ($mode === 'everyone') {
            $chatMessage->forceFill(['deleted_for_everyone_at' => now()])->save();
            return response()->json(['message' => 'Message deleted for everyone.']);
        }

        $deletedBy = is_array($chatMessage->deleted_by) ? $chatMessage->deleted_by : [];
        if (!in_array((int) $user->id, $deletedBy, true)) {
            $deletedBy[] = (int) $user->id;
            $chatMessage->forceFill(['deleted_by' => $deletedBy])->save();
        }

        return response()->json(['message' => 'Message deleted for you.']);
    }

    public function clearConversation(Request $request, int $userId)
    {
        $user = $request->user();
        $mode = $request->query('mode', 'me');

        $messages = ChatMessage::where(function ($query) use ($user, $userId) {
            $query->where(function ($thread) use ($user, $userId) {
                $thread->where('user_id', $user->id)->where('recipient_user_id', $userId);
            })->orWhere(function ($thread) use ($user, $userId) {
                $thread->where('user_id', $userId)->where('recipient_user_id', $user->id);
            });
        })->get();

        foreach ($messages as $message) {
            if ($mode === 'everyone') {
                $message->forceFill(['deleted_for_everyone_at' => now()])->save();
                continue;
            }

            $deletedBy = is_array($message->deleted_by) ? $message->deleted_by : [];
            if (!in_array((int) $user->id, $deletedBy, true)) {
                $deletedBy[] = (int) $user->id;
                $message->forceFill(['deleted_by' => $deletedBy])->save();
            }
        }

        return response()->json(['message' => $mode === 'everyone' ? 'Conversation deleted for everyone.' : 'Conversation deleted for you.']);
    }
}