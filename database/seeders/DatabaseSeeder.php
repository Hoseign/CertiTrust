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
            ['name' => 'CertiTrust UCU Admin', 'role' => 'admin', 'university_code' => 'UCU', 'password' => bcrypt('certitrust256')]
        );
        User::updateOrCreate(
            ['email' => 'randygonzales2024@gmail.com'],
            ['name' => 'CertiTrust PSU Admin', 'role' => 'admin', 'university_code' => 'PSU', 'password' => bcrypt('certitrust256')]
        );
    }
}
