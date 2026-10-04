<?php

namespace App\Http\Controllers;

use App\Models\ChatMessage;
use App\Models\Certificate;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Carbon;

class ChatController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();
        $isSuperAdmin = $this->isSuperAdmin($user);

        if (!$isSuperAdmin && !$user->university_code) {
            return response()->json(['message' => 'Your account is not assigned to a school.'], 403);
        }

        $query = ChatMessage::query()->with('replyTo:id,user_id,sender_name,message')
            ->orderBy('created_at');
        if (!$isSuperAdmin) {
            $query->where('university_code', $user->university_code);
        }

        $targetId = $request->integer('with_user_id') ?: $request->integer('student_id');
        if ($targetId) {
            $target = User::find($targetId);
            if (!$target || !$this->canChatWith($user, $target)) {
                return response()->json(['message' => 'This contact is not available to your account.'], 403);
            }
            ChatMessage::where('user_id', $targetId)
                ->where('recipient_user_id', $user->id)
                ->whereNull('delivered_at')
                ->whereNull('deleted_for_everyone_at')
                ->update(['delivered_at' => now()]);
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
        $search = strtolower(trim((string) $request->query('search', '')));
        $isSuperAdmin = $this->isSuperAdmin($user);

        if ($isSuperAdmin) {
            $contacts = User::where('role', 'admin')
                ->whereNotNull('university_code')
                ->orderBy('name')
                ->get()
                ->map(fn (User $admin) => $this->contactProfile($admin, [
                    'name' => $admin->name ?: 'School Admin',
                    'university_code' => $admin->university_code,
                    'role_label' => 'School administrator',
                ]));
            $reporterIds = ChatMessage::where('recipient_user_id', $user->id)
                ->where('is_report', true)
                ->distinct()
                ->pluck('user_id');
            $reporters = User::whereIn('id', $reporterIds)
                ->where('role', 'student')
                ->get()
                ->map(function (User $student) {
                    $certificate = $this->studentCertificateFor($student);
                    return $this->contactProfile($student, [
                        'name' => $certificate?->student_name ?: $certificate?->recipient_name ?: $student->name,
                        'student_id' => $certificate?->student_id,
                        'degree' => $certificate?->degree ?: $certificate?->course_or_event,
                        'issue_date' => $certificate?->issue_date,
                        'certificate_code' => $certificate?->certificate_code,
                        'cert_hash' => $certificate?->cert_hash,
                        'university_code' => $certificate?->university_code ?: $student->university_code,
                        'role_label' => 'Student report',
                        'is_report_contact' => true,
                    ]);
                });
            $contacts = $contacts->concat($reporters);
        } elseif ($user->role === 'admin') {
            if (!$user->university_code) {
                return response()->json(['message' => 'Your account is not assigned to a school.'], 403);
            }
            $certificates = Certificate::where('university_code', $user->university_code)
                ->orderByDesc('issue_date')
                ->get();
            $contacts = $certificates->map(function (Certificate $certificate) {
                $email = strtolower(trim((string) ($certificate->student_email ?: $certificate->email)));
                $student = User::whereRaw('LOWER(TRIM(email)) = ?', [$email])
                    ->where('role', 'student')
                    ->first();
                if (!$student) return null;

                return $this->contactProfile($student, [
                    'name' => $certificate->student_name ?: $certificate->recipient_name ?: $student->name,
                    'email' => $email,
                    'student_id' => $certificate->student_id,
                    'degree' => $certificate->degree ?: $certificate->course_or_event,
                    'issue_date' => $certificate->issue_date,
                    'certificate_code' => $certificate->certificate_code,
                    'cert_hash' => $certificate->cert_hash,
                    'university_code' => $certificate->university_code,
                    'role_label' => 'Student',
                ]);
            })->filter()->unique('id')->values();

            $superAdmin = User::whereRaw('LOWER(email) = ?', ['certitrust256@gmail.com'])->first();
            if ($superAdmin) {
                $contacts->prepend($this->contactProfile($superAdmin, [
                    'name' => 'CertiTrust Super Admin',
                    'role_label' => 'System administrator',
                ]));
            }
        } else {
            if (!$user->university_code) {
                return response()->json(['data' => []]);
            }
            $certificate = Certificate::where('university_code', $user->university_code)
                ->where(function ($query) use ($user) {
                    $email = strtolower(trim($user->email));
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
                })
                ->latest('id')
                ->first();
            $admin = User::where('role', 'admin')
                ->where('university_code', $user->university_code)
                ->first();
            $contacts = $admin && $certificate
                ? collect([$this->contactProfile($admin, [
                    'name' => $admin->name ?: 'School Admin',
                    'student_id' => $certificate->student_id,
                    'student_email' => $certificate->student_email ?: $certificate->email,
                    'degree' => $certificate->degree ?: $certificate->course_or_event,
                    'issue_date' => $certificate->issue_date,
                    'certificate_code' => $certificate->certificate_code,
                    'cert_hash' => $certificate->cert_hash,
                    'university_code' => $certificate->university_code,
                    'role_label' => 'School administrator',
                ])])
                : collect();
            $superAdmin = User::whereRaw('LOWER(TRIM(email)) = ?', ['certitrust256@gmail.com'])->first();
            if ($superAdmin && $certificate) {
                $contacts->push($this->contactProfile($superAdmin, [
                    'name' => 'CertiTrust Super Admin',
                    'student_id' => $certificate->student_id,
                    'degree' => $certificate->degree ?: $certificate->course_or_event,
                    'issue_date' => $certificate->issue_date,
                    'certificate_code' => $certificate->certificate_code,
                    'cert_hash' => $certificate->cert_hash,
                    'university_code' => $certificate->university_code,
                    'role_label' => 'Report to Super Admin',
                    'is_report_contact' => true,
                ]));
            }
        }

        if ($search !== '') {
            $contacts = $contacts->filter(function (array $contact) use ($search) {
                foreach (['name', 'email', 'student_id', 'degree', 'certificate_code', 'university_code'] as $field) {
                    if (str_contains(strtolower((string) ($contact[$field] ?? '')), $search)) return true;
                }
                return false;
            });
        }

        return response()->json(['data' => $contacts->values()]);
    }

    public function presence(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        $contacts = $this->contactsFor($user);

        return response()->json(['data' => $contacts]);
    }

    public function store(Request $request)
    {
        $user = $request->user();
        $user->forceFill(['last_seen_at' => now()])->save();

        $validated = $request->validate([
            'message' => ['nullable', 'string', 'max:2000'],
            'recipient_user_id' => ['nullable', 'integer', 'exists:users,id'],
            'attachment' => ['nullable', 'file', 'mimes:jpg,jpeg,png,gif,mp4,mov,webm', 'max:51200'],
            'reply_to_id' => ['nullable', 'integer', 'exists:chat_messages,id'],
            'is_report' => ['nullable', 'boolean'],
        ]);

        if (!$user->university_code && !$this->isSuperAdmin($user)) {
            return response()->json(['message' => 'Your account is not assigned to a school.'], 403);
        }

        $recipient = User::find($validated['recipient_user_id'] ?? null);
        if (!$recipient || !$this->canChatWith($user, $recipient)) {
            return response()->json(['message' => 'Select a valid contact from your conversation list.'], 422);
        }
        $isReport = (bool) ($validated['is_report'] ?? false);
        if ($isReport && ($user->role !== 'student' || !$this->isSuperAdmin($recipient))) {
            return response()->json(['message' => 'Only students can report a school administrator to the Super Admin.'], 403);
        }
        $replyTo = null;
        if (!empty($validated['reply_to_id'])) {
            $replyTo = ChatMessage::find($validated['reply_to_id']);
            if (!$replyTo || !(
                ((int) $replyTo->user_id === (int) $user->id && (int) $replyTo->recipient_user_id === (int) $recipient->id) ||
                ((int) $replyTo->user_id === (int) $recipient->id && (int) $replyTo->recipient_user_id === (int) $user->id)
            )) {
                return response()->json(['message' => 'The message being replied to is not in this conversation.'], 422);
            }
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
            'recipient_user_id' => $recipient->id,
            'university_code' => $user->university_code ?: $recipient->university_code,
            'sender_email' => $user->email,
            'sender_name' => $user->name,
            'message' => $validated['message'] ?? '',
            'attachment_url' => $attachmentUrl,
            'attachment_type' => $attachmentType,
            'reply_to_id' => $replyTo?->id,
            'is_report' => $isReport,
            'deleted_by' => [],
        ]);

        return response()->json(['data' => $message->load('replyTo:id,user_id,sender_name,message')], 201);
    }

    private function contactsFor(User $user)
    {
        $isSuperAdmin = $this->isSuperAdmin($user);
        if ($isSuperAdmin) {
            $targets = User::where('role', 'admin')->whereNotNull('university_code')->get();
            $reporterIds = ChatMessage::where('recipient_user_id', $user->id)
                ->where('is_report', true)->distinct()->pluck('user_id');
            $targets = $targets->concat(User::whereIn('id', $reporterIds)->where('role', 'student')->get());
        } elseif ($user->role === 'admin') {
            $studentEmails = Certificate::where('university_code', $user->university_code)
                ->pluck('student_email')->filter()->map(fn ($email) => strtolower(trim($email)))->unique();
            $targets = User::where('role', 'student')
                ->whereIn(DB::raw('LOWER(TRIM(email))'), $studentEmails->all())->get();
            $superAdmin = User::whereRaw('LOWER(email) = ?', ['certitrust256@gmail.com'])->first();
            if ($superAdmin) $targets->prepend($superAdmin);
        } else {
            if (!$user->university_code) return collect();
            $hasCredential = Certificate::where('university_code', $user->university_code)
                ->where(function ($query) use ($user) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [strtolower(trim($user->email))])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [strtolower(trim($user->email))]);
                })->exists();
            if (!$hasCredential) return collect();
            $targets = User::where('role', 'admin')->where('university_code', $user->university_code)->get();
            $superAdmin = User::whereRaw('LOWER(TRIM(email)) = ?', ['certitrust256@gmail.com'])->first();
            if ($superAdmin) $targets->push($superAdmin);
        }

        return $targets->map(function (User $target) use ($user) {
            $certificate = null;
            if ($target->role === 'student') {
                $certificate = $this->studentCertificateFor($target);
            } elseif ($user->role !== 'admin') {
                $certificate = $this->studentCertificateFor($user);
            }

            $details = $certificate ? [
                'student_id' => $certificate->student_id,
                'student_email' => $certificate->student_email ?: $certificate->email,
                'degree' => $certificate->degree ?: $certificate->course_or_event,
                'issue_date' => $certificate->issue_date,
                'certificate_code' => $certificate->certificate_code,
                'cert_hash' => $certificate->cert_hash,
                'university_code' => $certificate->university_code,
            ] : [];

            return $this->contactProfile($target, array_merge($details, [
                'name' => $certificate
                    ? ($certificate->student_name ?: $certificate->recipient_name ?: $target->name)
                    : ($this->isSuperAdmin($target) ? 'CertiTrust Super Admin' : $target->name),
                'role_label' => $this->isSuperAdmin($target)
                    ? 'System administrator'
                    : ($target->role === 'admin' ? 'School administrator' : 'Student'),
            ]));
        })->unique('id')->values();
    }

    private function contactProfile(User $target, array $details = []): array
    {
        $lastSeen = $target->last_seen_at;

        return array_merge([
            'id' => $target->id,
            'email' => $target->email,
            'university_code' => $target->university_code,
            'profile_image_url' => $target->profile_image_url,
            'profile_icon' => $target->profile_icon,
            'profile_logo' => $this->isSuperAdmin($target)
                ? 'web/assets/images/certitrustlogo.png'
                : ($target->role === 'admin' ? $this->schoolLogo($target->university_code) : null),
            'is_active' => $lastSeen?->greaterThan(now()->subMinutes(5)) ?? false,
            'last_seen_label' => $lastSeen ? 'Last active: ' . $lastSeen->diffForHumans() : 'Last active: never',
        ], $details);
    }

    private function canChatWith(User $user, User $target): bool
    {
        if ($user->is($target)) return false;
        if ($this->isSuperAdmin($user)) {
            if ($target->role === 'admin' && $target->university_code !== null) return true;
            return $target->role === 'student' && ChatMessage::where('user_id', $target->id)
                ->where('recipient_user_id', $user->id)->where('is_report', true)->exists();
        }
        if ($user->role === 'admin') {
            if ($this->isSuperAdmin($target)) return true;
            if ($target->role !== 'student' || $target->university_code !== $user->university_code) return false;
            $email = strtolower(trim($target->email));

            return Certificate::where('university_code', $user->university_code)
                ->where(function ($query) use ($email) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
                })->exists();
        }

        if ($this->isSuperAdmin($target)) {
            if ($user->role !== 'student') return false;
            $email = strtolower(trim($user->email));
            return Certificate::where('university_code', $user->university_code)
                ->where(function ($query) use ($email) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
                })->exists();
        }
        if ($target->role !== 'admin' || $target->university_code !== $user->university_code) return false;
        $email = strtolower(trim($user->email));

        return Certificate::where('university_code', $user->university_code)
            ->where(function ($query) use ($email) {
                $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                    ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
            })->exists();
    }

    private function isSuperAdmin(User $user): bool
    {
        return strtolower(trim($user->email)) === 'certitrust256@gmail.com';
    }

    private function studentCertificateFor(User $student): ?Certificate
    {
        $email = strtolower(trim($student->email));
        return Certificate::where(function ($query) use ($email) {
            $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$email])
                ->orWhereRaw('LOWER(TRIM(email)) = ?', [$email]);
        })->latest('issue_date')->first();
    }

    private function schoolLogo(?string $school): ?string
    {
        return match (strtoupper((string) $school)) {
            'PSU' => 'web/assets/images/PSU_LOGO.png',
            'UCU' => 'web/assets/images/UCU_LOGO.png',
            default => null,
        };
    }

    public function destroy(Request $request, ChatMessage $chatMessage)
    {
        $user = $request->user();
        $mode = $request->query('mode', 'me');
        $otherUserId = (int) $chatMessage->user_id === (int) $user->id
            ? $chatMessage->recipient_user_id
            : $chatMessage->user_id;
        $otherUser = $otherUserId ? User::find($otherUserId) : null;

        if (!$otherUser || !$this->canChatWith($user, $otherUser)) {
            return response()->json(['message' => 'This message is not in your conversation.'], 403);
        }

        if ($mode === 'everyone') {
            if ((int) $chatMessage->user_id !== (int) $user->id) {
                return response()->json(['message' => 'Only the sender can delete a message for everyone.'], 403);
            }
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
        $target = User::find($userId);
        if (!$target || !$this->canChatWith($user, $target)) {
            return response()->json(['message' => 'This conversation is not available to your account.'], 403);
        }
        if ($mode === 'everyone') {
            ChatMessage::where(function ($query) use ($user, $userId) {
                $query->where(function ($thread) use ($user, $userId) {
                    $thread->where('user_id', $user->id)->where('recipient_user_id', $userId);
                })->orWhere(function ($thread) use ($user, $userId) {
                    $thread->where('user_id', $userId)->where('recipient_user_id', $user->id);
                });
            })->update(['deleted_for_everyone_at' => now()]);

            return response()->json(['message' => 'Conversation deleted for everyone.']);
        }

        $messages = ChatMessage::where(function ($query) use ($user, $userId) {
            $query->where(function ($thread) use ($user, $userId) {
                $thread->where('user_id', $user->id)->where('recipient_user_id', $userId);
            })->orWhere(function ($thread) use ($user, $userId) {
                $thread->where('user_id', $userId)->where('recipient_user_id', $user->id);
            });
        })->get();

        foreach ($messages as $message) {
            $deletedBy = is_array($message->deleted_by) ? $message->deleted_by : [];
            if (!in_array((int) $user->id, $deletedBy, true)) {
                $deletedBy[] = (int) $user->id;
                $message->forceFill(['deleted_by' => $deletedBy])->save();
            }
        }

        return response()->json(['message' => 'Conversation deleted for you.']);
    }
}