<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SupabaseChatStorage
{
    private const ALLOWED_MIME_TYPES = [
        'image/jpeg',
        'image/png',
        'image/gif',
        'video/mp4',
        'video/quicktime',
        'video/webm',
    ];

    public function upload(UploadedFile $file): array
    {
        $baseUrl = rtrim((string) config('services.supabase.url'), '/');
        $serviceRoleKey = (string) config('services.supabase.service_role_key');
        $bucket = (string) config('services.supabase.chat_bucket', 'chat-attachments');
        if ($baseUrl === '' || $serviceRoleKey === '' || $bucket === '') {
            return [
                'status' => 503,
                'message' => 'Chat file storage is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on the backend.',
            ];
        }

        $mimeType = $file->getMimeType() ?: 'application/octet-stream';
        if (!in_array($mimeType, self::ALLOWED_MIME_TYPES, true)) {
            return [
                'status' => 422,
                'message' => 'This chat attachment type is not supported.',
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
                        'public' => false,
                        'file_size_limit' => 50 * 1024 * 1024,
                        'allowed_mime_types' => self::ALLOWED_MIME_TYPES,
                    ]);
                if (!$created->successful() && $created->status() !== 409) {
                    return $this->storageError(
                        'create the chat attachment bucket',
                        $created->status(),
                        $created->json('message') ?? $created->json('error'),
                    );
                }
            } elseif (!$bucketResponse->successful()) {
                return $this->storageError(
                    'check the chat attachment bucket',
                    $bucketResponse->status(),
                    $bucketResponse->json('message') ?? $bucketResponse->json('error'),
                );
            } elseif ($bucketResponse->json('public') === true) {
                $updated = Http::connectTimeout(3)
                    ->timeout(8)
                    ->withHeaders($headers)
                    ->put($baseUrl . '/storage/v1/bucket/' . rawurlencode($bucket), [
                        'public' => false,
                    ]);
                if (!$updated->successful()) {
                    return $this->storageError(
                        'make the chat attachment bucket private',
                        $updated->status(),
                        $updated->json('message') ?? $updated->json('error'),
                    );
                }
            } elseif ($bucketResponse->json('public') !== false) {
                return $this->storageError(
                    'verify the chat attachment bucket visibility',
                    502,
                    'Supabase did not report whether the bucket is private.',
                );
            }

            $extension = match ($mimeType) {
                'image/jpeg' => 'jpg',
                'image/png' => 'png',
                'image/gif' => 'gif',
                'video/mp4' => 'mp4',
                'video/quicktime' => 'mov',
                'video/webm' => 'webm',
                default => throw new \LogicException('Unsupported chat attachment MIME type.'),
            };
            $objectName = 'chat/' . Str::uuid() . '.' . $extension;
            $contents = $file->getContent();
            if ($contents === '') {
                return [
                    'status' => 422,
                    'message' => 'The selected chat attachment is empty.',
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
                    'upload the chat attachment',
                    $upload->status(),
                    $upload->json('message') ?? $upload->json('error'),
                );
            }

            return ['path' => $objectName];
        } catch (ConnectionException $exception) {
            Log::warning('Supabase Storage could not receive a chat attachment.', [
                'exception' => $exception->getMessage(),
            ]);

            return [
                'status' => 502,
                'message' => 'Chat file storage could not be reached. Please retry.',
            ];
        }
    }

    public function download(string $attachmentReference): array
    {
        $baseUrl = rtrim((string) config('services.supabase.url'), '/');
        $serviceRoleKey = (string) config('services.supabase.service_role_key');
        $bucket = (string) config('services.supabase.chat_bucket', 'chat-attachments');
        if ($baseUrl === '' || $serviceRoleKey === '' || $bucket === '') {
            return [
                'status' => 503,
                'message' => 'Chat file storage is not configured on the backend.',
            ];
        }
        $objectPath = $this->objectPath($attachmentReference, $baseUrl, $bucket);
        if ($objectPath === null) {
            return ['status' => 404, 'message' => 'Chat attachment not found.'];
        }

        $headers = ['apikey' => $serviceRoleKey];
        if (str_starts_with($serviceRoleKey, 'eyJ')) {
            $headers['Authorization'] = 'Bearer ' . $serviceRoleKey;
        }

        try {
            $bucketResponse = Http::connectTimeout(3)
                ->timeout(8)
                ->withHeaders($headers)
                ->get($baseUrl . '/storage/v1/bucket/' . rawurlencode($bucket));
            if (!$bucketResponse->successful()) {
                return $this->storageError(
                    'verify the chat attachment bucket privacy',
                    $bucketResponse->status(),
                    $bucketResponse->json('message') ?? $bucketResponse->json('error'),
                );
            }
            if ($bucketResponse->json('public') === true) {
                $updated = Http::connectTimeout(3)
                    ->timeout(8)
                    ->withHeaders($headers)
                    ->put($baseUrl . '/storage/v1/bucket/' . rawurlencode($bucket), [
                        'public' => false,
                    ]);
                if (!$updated->successful()) {
                    return $this->storageError(
                        'make the chat attachment bucket private',
                        $updated->status(),
                        $updated->json('message') ?? $updated->json('error'),
                    );
                }
            } elseif ($bucketResponse->json('public') !== false) {
                return $this->storageError(
                    'verify the chat attachment bucket visibility',
                    502,
                    'Supabase did not report whether the bucket is private.',
                );
            }

            $response = Http::connectTimeout(3)
                ->timeout(20)
                ->withHeaders($headers)
                ->get($baseUrl . '/storage/v1/object/' . rawurlencode($bucket) . '/' . $objectPath);

            if (!$response->successful()) {
                return ['status' => $response->status() === 404 ? 404 : 502, 'message' => 'Chat attachment could not be loaded.'];
            }

            return [
                'body' => $response->body(),
                'content_type' => $response->header('Content-Type') ?: 'application/octet-stream',
            ];
        } catch (ConnectionException $exception) {
            Log::warning('Supabase Storage could not provide a chat attachment.', [
                'exception' => $exception->getMessage(),
            ]);

            return ['status' => 502, 'message' => 'Chat file storage could not be reached.'];
        }
    }

    private function objectPath(string $reference, string $baseUrl, string $bucket): ?string
    {
        $path = $reference;
        if (filter_var($reference, FILTER_VALIDATE_URL) !== false) {
            $url = parse_url($reference);
            $base = parse_url($baseUrl);
            if (
                !is_array($url)
                || !is_array($base)
                || strtolower((string) ($url['host'] ?? '')) !== strtolower((string) ($base['host'] ?? ''))
            ) {
                return null;
            }

            $bucketPath = rawurlencode($bucket);
            $prefixes = [
                '/storage/v1/object/public/' . $bucketPath . '/',
                '/storage/v1/object/' . $bucketPath . '/',
            ];
            $path = (string) ($url['path'] ?? '');
            foreach ($prefixes as $prefix) {
                if (str_starts_with($path, $prefix)) {
                    $path = substr($path, strlen($prefix));
                    break;
                }
            }
            if ($path === (string) ($url['path'] ?? '')) {
                return null;
            }
        } elseif (str_contains($reference, '://')) {
            return null;
        }

        $segments = array_map('rawurldecode', explode('/', trim($path, '/')));
        if (
            count($segments) < 2
            || $segments[0] !== 'chat'
            || in_array('', $segments, true)
            || in_array('.', $segments, true)
            || in_array('..', $segments, true)
        ) {
            return null;
        }

        return implode('/', array_map('rawurlencode', $segments));
    }

    private function storageError(
        string $operation,
        int $status,
        ?string $details = null,
    ): array
    {
        Log::warning('Supabase Storage rejected a chat attachment operation.', [
            'operation' => $operation,
            'status' => $status,
            'details' => $details,
        ]);

        return [
            'status' => 502,
            'message' => 'Supabase Storage could not ' . $operation . ' (HTTP ' . $status . ').'
                . ($details ? ' ' . $details : ' Check the chat bucket and service role key.'),
        ];
    }
}
