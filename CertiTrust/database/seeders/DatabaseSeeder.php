<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        User::updateOrCreate(
            ['email' => 'certitrust256@gmail.com'],
            ['name' => 'CertiTrust Super Admin', 'role' => 'admin', 'university_code' => null, 'password' => bcrypt('certitrust256')]
        );
    }
}
