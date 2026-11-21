<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SupabaseProfileImageStorage
{
    private const ALLOWED_MIME_TYPES = [
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
    ];

    public function upload(UploadedFile $file): array
    {
        $baseUrl = rtrim((string) config('services.supabase.url'), '/');
        $serviceRoleKey = (string) config('services.supabase.service_role_key');
        $bucket = (string) config('services.supabase.profile_bucket', 'profile-images');
        if ($baseUrl === '' || $serviceRoleKey === '' || $bucket === '') {
            return [
                'status' => 503,
                'message' => 'Profile image storage is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on the backend.',
            ];
        }

        $mimeType = $file->getMimeType() ?: 'application/octet-stream';
        if (!in_array($mimeType, self::ALLOWED_MIME_TYPES, true)) {
            return [
                'status' => 422,
                'message' => 'This profile image type is not supported.',
            ];
        }

        $headers = ['apikey' => $serviceRoleKey];
        if (str_starts_with($serviceRoleKey, 'eyJ')) {
            $headers['Authorization'] = 'Bearer ' . $serviceRoleKey;
        }

        try {
            $bucketEndpoint = $baseUrl . '/storage/v1/bucket/' . rawurlencode($bucket);
            $bucketResponse = Http::connectTimeout(3)
                ->timeout(8)
                ->withHeaders($headers)
                ->get($bucketEndpoint);
            $bucketError = strtolower(implode(' ', array_filter([
                $bucketResponse->json('message'),
                $bucketResponse->json('error'),
                $bucketResponse->json('statusCode'),
            ], 'is_string')));
            $bucketDoesNotExist = $bucketResponse->status() === 404
                || ($bucketResponse->status() === 400
                    && str_contains($bucketError, 'bucket not found'));

            if ($bucketDoesNotExist) {
                $created = Http::connectTimeout(3)
                    ->timeout(8)
                    ->withHeaders($headers)
                    ->post($baseUrl . '/storage/v1/bucket', [
                        'id' => $bucket,
                        'name' => $bucket,
                        'public' => true,
                        'file_size_limit' => 5 * 1024 * 1024,
                        'allowed_mime_types' => self::ALLOWED_MIME_TYPES,
                    ]);
                if (!$created->successful() && $created->status() !== 409) {
                    return $this->storageError(
                        'create the profile image bucket',
                        $created->status(),
                        $created->json('message') ?? $created->json('error'),
                    );
                }
            } elseif (!$bucketResponse->successful()) {
                return $this->storageError(
                    'check the profile image bucket',
                    $bucketResponse->status(),
                    $bucketResponse->json('message') ?? $bucketResponse->json('error'),
                );
            } elseif ($bucketResponse->json('public') === false) {
                $updated = Http::connectTimeout(3)
                    ->timeout(8)
                    ->withHeaders($headers)
                    ->put($bucketEndpoint, ['public' => true]);
                if (!$updated->successful()) {
                    return $this->storageError(
                        'make the profile image bucket public',
                        $updated->status(),
                        $updated->json('message') ?? $updated->json('error'),
                    );
                }
            } elseif ($bucketResponse->json('public') !== true) {
                return $this->storageError(
                    'verify the profile image bucket visibility',
                    502,
                    'Supabase did not report whether the bucket is public.',
                );
            }

            $extension = match ($mimeType) {
                'image/jpeg' => 'jpg',
                'image/png' => 'png',
                'image/webp' => 'webp',
                'image/gif' => 'gif',
                default => throw new \LogicException('Unsupported profile image MIME type.'),
            };
            $objectName = 'profiles/' . Str::uuid() . '.' . $extension;
            $contents = $file->getContent();
            if ($contents === '') {
                return [
                    'status' => 422,
                    'message' => 'The selected profile image is empty.',
                ];
            }

            $upload = Http::connectTimeout(3)
                ->timeout(30)
                ->withHeaders($headers + [
                    'x-upsert' => 'false',
                    'Content-Type' => $mimeType,
                ])
                ->withBody($contents, $mimeType)
                ->post(
                    $baseUrl . '/storage/v1/object/' . rawurlencode($bucket) . '/'
                        . implode('/', array_map('rawurlencode', explode('/', $objectName))),
                );
            if (!$upload->successful()) {
                return $this->storageError(
                    'upload the profile image',
                    $upload->status(),
                    $upload->json('message') ?? $upload->json('error'),
                );
            }

            return [
                'url' => $baseUrl . '/storage/v1/object/public/' . rawurlencode($bucket) . '/'
                    . implode('/', array_map('rawurlencode', explode('/', $objectName))),
            ];
        } catch (ConnectionException $exception) {
            Log::warning('Supabase Storage could not receive a profile image.', [
                'exception' => $exception->getMessage(),
            ]);

            return [
                'status' => 502,
                'message' => 'Profile image storage could not be reached. Please retry.',
            ];
        }
    }

    private function storageError(string $operation, int $status, ?string $details = null): array
    {
        Log::warning('Supabase Storage rejected a profile image operation.', [
            'operation' => $operation,
            'status' => $status,
            'details' => $details,
        ]);

        return [
            'status' => 502,
            'message' => 'Supabase Storage could not ' . $operation . ' (HTTP ' . $status . ').'
                . ($details ? ' ' . $details : ' Check the profile image bucket and service role key.'),
        ];
    }
}
