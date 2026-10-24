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

            if ($bucketResponse->status() === 404) {
                $created = Http::connectTimeout(3)
                    ->timeout(8)
                    ->withHeaders($headers)
                    ->post($baseUrl . '/storage/v1/bucket', [
                        'id' => $bucket,
                        'name' => $bucket,
                        'public' => true,
                        'file_size_limit' => 50 * 1024 * 1024,
                        'allowed_mime_types' => self::ALLOWED_MIME_TYPES,
                    ]);
                if (!$created->successful() && $created->status() !== 409) {
                    return $this->storageError('create the chat attachment bucket', $created->status());
                }
                if ($created->status() === 409) {
                    $bucketResponse = Http::connectTimeout(3)
                        ->timeout(8)
                        ->withHeaders($headers)
                        ->get($bucketEndpoint);
                } else {
                    $bucketResponse = $created;
                }
            }

            if (!$bucketResponse->successful()) {
                return $this->storageError('check the chat attachment bucket', $bucketResponse->status());
            }
            if (($bucketResponse->json('public') ?? true) !== true) {
                return [
                    'status' => 503,
                    'message' => 'The configured chat attachment bucket must be public so conversation participants can view files.',
                ];
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
            $upload = Http::connectTimeout(3)
                ->timeout(30)
                ->withHeaders($headers + [
                    'x-upsert' => 'false',
                    'Content-Type' => $mimeType,
                ])
                ->withBody($file->getContent(), $mimeType)
                ->post(
                    $baseUrl . '/storage/v1/object/' . rawurlencode($bucket) . '/'
                        . implode('/', array_map('rawurlencode', explode('/', $objectName))),
                );

            if (!$upload->successful()) {
                return $this->storageError('upload the chat attachment', $upload->status());
            }

            return [
                'url' => $baseUrl . '/storage/v1/object/public/'
                    . rawurlencode($bucket) . '/'
                    . implode('/', array_map('rawurlencode', explode('/', $objectName))),
            ];
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

    private function storageError(string $operation, int $status): array
    {
        Log::warning('Supabase Storage rejected a chat attachment operation.', [
            'operation' => $operation,
            'status' => $status,
        ]);

        return [
            'status' => 502,
            'message' => 'Supabase Storage could not ' . $operation . ' (HTTP ' . $status . '). Check the chat bucket and service role key.',
        ];
    }
}
