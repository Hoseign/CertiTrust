<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'supabase' => [
        'url' => env('SUPABASE_URL'),
        'service_role_key' => env('SUPABASE_SERVICE_ROLE_KEY'),
        'diploma_bucket' => env('SUPABASE_DIPLOMA_BUCKET', 'diplomas'),
    ],

    'certitrust' => [
        'enabled' => env('CERTITRUST_CHAIN_ENABLED', false),
        'rpc_url' => env('CERTITRUST_RPC_URL', 'https://rpc.sepolia.org'),
        'rpc_fallback_urls' => array_filter(array_map('trim', explode(',', (string) env(
            'CERTITRUST_RPC_FALLBACK_URLS',
            'https://ethereum-sepolia-rpc.publicnode.com,https://sepolia.drpc.org,https://1rpc.io/sepolia'
        )))),
        'chain_id' => env('CERTITRUST_CHAIN_ID', 11155111),
        'network' => env('CERTITRUST_NETWORK', 'ethereum-sepolia'),
        'contract_address' => env('CERTITRUST_CONTRACT_ADDRESS'),
        'private_key' => env('CERTITRUST_SIGNER_PRIVATE_KEY'),
    ],

];
