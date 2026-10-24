<?php

return [
    'paths' => ['api/*', 'sanctum/csrf-cookie', 'login', 'logout', 'user'],
    'allowed_methods' => ['*'],
    'allowed_origins' => array_values(array_filter([
        env('WEB_APP_URL'),
        env('APP_URL'),
        'http://localhost:5173',
        'http://127.0.0.1:5173',
        'http://localhost:8000',
        'https://certitrust-yhzl.onrender.com',
    ])),
    'allowed_origins_patterns' => [
        '/^https?:\/\/localhost(:\d+)?$/',
        '/^https?:\/\/127\.0\.0\.1(:\d+)?$/',
        '/^https:\/\/certitrust-yhzl\.onrender\.com$/',
    ],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => true,
];