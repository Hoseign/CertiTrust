<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SuperAdminGoogleLoginTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_password_login_is_disabled(): void
    {
        User::create([
            'name' => 'CertiTrust Super Admin',
            'email' => 'certitrust256@gmail.com',
            'password' => Hash::make('old-seeded-password'),
            'role' => 'admin',
        ]);

        $this->postJson('/api/login', [
            'email' => 'certitrust256@gmail.com',
            'password' => 'old-seeded-password',
        ])->assertForbidden()
            ->assertJsonPath('message', 'This account must sign in with Google.');

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_google_login_provisions_the_super_admin_without_a_seeded_password(): void
    {
        Http::fake([
            'https://www.googleapis.com/oauth2/v3/userinfo' => Http::response([
                'email' => 'certitrust256@gmail.com',
                'email_verified' => true,
                'name' => 'CertiTrust Super Admin',
                'sub' => 'certitrust-super-admin-google-id',
            ], 200),
        ]);

        $this->assertDatabaseMissing('users', ['email' => 'certitrust256@gmail.com']);

        $this->postJson('/api/auth/google', ['access_token' => 'valid-google-token'])
            ->assertOk()
            ->assertJsonPath('email', 'certitrust256@gmail.com')
            ->assertJsonPath('role', 'admin')
            ->assertJsonPath('university_code', null);

        $user = User::where('email', 'certitrust256@gmail.com')->firstOrFail();
        $this->assertSame('certitrust-super-admin-google-id', $user->google_id);
        $this->assertFalse(Hash::check('certitrust256', $user->password));
        $this->assertFalse(Hash::check('old-seeded-password', $user->password));
    }

    public function test_database_seeder_does_not_create_a_default_account_or_delete_existing_users(): void
    {
        $admin = User::create([
            'name' => 'Existing Admin',
            'email' => 'existing-admin@example.edu',
            'password' => Hash::make('secret'),
            'role' => 'admin',
            'university_code' => 'PSU',
        ]);

        $this->seed();

        $this->assertDatabaseHas('users', ['id' => $admin->id]);
        $this->assertDatabaseMissing('users', ['email' => 'certitrust256@gmail.com']);
    }
}
