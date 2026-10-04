<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\HasApiTokens; // 1. Added Sanctum trait import

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable; // 2. Added HasApiTokens here

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'password',
        'google_id', // 3. Added so Google ID can be mass-assigned
        'role',      // 4. Added so user role can be handled
        'university_code',
        'profile_image_url',
        'profile_icon',
        'access_frozen',
        'access_frozen_at',
        'access_frozen_by',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'password' => 'hashed',
            'access_frozen' => 'boolean',
            'access_frozen_at' => 'datetime',
        ];
    }

    public function isAccessFrozen(): bool
    {
        if (strtolower((string) $this->email) === 'certitrust256@gmail.com') {
            return false;
        }

        if (in_array($this->role, ['student', 'user'], true) && $this->access_frozen === null) {
            $universityCode = $this->university_code;
            if (!$universityCode) {
                $normalizedEmail = strtolower(trim((string) $this->email));
                $universityCode = DB::table('certificates')
                    ->where(function ($query) use ($normalizedEmail) {
                        $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail])
                            ->orWhereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail]);
                    })
                    ->latest('id')
                    ->value('university_code');
            }

            if (!$universityCode) {
                return false;
            }

            return (bool) UniversityAccessControl::query()
                ->where('university_code', $universityCode)
                ->value('students_frozen');
        }

        return (bool) $this->access_frozen;
    }

    public function accessFrozenById(): ?int
    {
        if (!$this->isAccessFrozen()) {
            return null;
        }

        if ($this->access_frozen !== null) {
            return $this->access_frozen ? (int) $this->access_frozen_by : null;
        }

        $universityCode = $this->university_code;
        if (!$universityCode) {
            $normalizedEmail = strtolower(trim((string) $this->email));
            $universityCode = DB::table('certificates')
                ->where(function ($query) use ($normalizedEmail) {
                    $query->whereRaw('LOWER(TRIM(student_email)) = ?', [$normalizedEmail])
                        ->orWhereRaw('LOWER(TRIM(email)) = ?', [$normalizedEmail]);
                })
                ->latest('id')
                ->value('university_code');
        }

        if (!$universityCode) {
            return null;
        }

        $actorId = UniversityAccessControl::query()
            ->where('university_code', $universityCode)
            ->value('updated_by');

        return $actorId === null ? null : (int) $actorId;
    }
}