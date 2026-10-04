<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SupabaseDiplomaStorage
{
    public function upload(UploadedFile $file): array
    {
        $configuration = $this->configuration();
        if ($configuration['error']) {
            return $configuration['error'];
        }

        [$baseUrl, $serviceRoleKey, $bucket] = $configuration['values'];
        $headers = $this->headers($serviceRoleKey);
        $bucketEndpoint = $baseUrl . '/storage/v1/bucket/' . rawurlencode($bucket);

        try {
            $bucketResponse = Http::timeout(15)
                ->withHeaders($headers)
                ->get($bucketEndpoint);

            if ($bucketResponse->status() === 404) {
                $createdBucket = Http::timeout(15)
                    ->withHeaders($headers)
                    ->post($baseUrl . '/storage/v1/bucket', [
                        'id' => $bucket,
                        'name' => $bucket,
                        'public' => true,
                        'file_size_limit' => 20 * 1024 * 1024,
                        'allowed_mime_types' => [
                            'application/pdf',
                            'image/jpeg',
                            'image/png',
                        ],
                    ]);

                if (!$createdBucket->successful() && $createdBucket->status() !== 409) {
                    return $this->httpError('create the diploma bucket', $createdBucket->status());
                }
            } elseif (!$bucketResponse->successful()) {
                return $this->httpError(
                    'check the diploma bucket',
                    $bucketResponse->status(),
                    false,
                    $bucketResponse->json('message'),
                );
            }

            $extension = strtolower($file->getClientOriginalExtension()) ?: 'bin';
            $objectName = Str::uuid() . '.' . $extension;
            $contents = $file->getContent();
            if ($contents === '') {
                return [
                    'status' => 422,
                    'message' => 'The selected diploma file is empty.',
                ];
            }
            $uploadResponse = Http::timeout(30)
                ->withHeaders($headers + [
                    'x-upsert' => 'false',
                    'Content-Type' => $file->getMimeType() ?: 'application/octet-stream',
                ])
                ->withBody($contents, $file->getMimeType() ?: 'application/octet-stream')
                ->post(
                    $baseUrl . '/storage/v1/object/' . rawurlencode($bucket) . '/' . rawurlencode($objectName),
                );

            if (!$uploadResponse->successful()) {
                return $this->httpError(
                    'upload the diploma',
                    $uploadResponse->status(),
                    false,
                    $uploadResponse->json('message'),
                );
            }
        } catch (ConnectionException $exception) {
            Log::warning('Could not connect to Supabase Storage.', [
                'exception' => $exception->getMessage(),
            ]);

            return [
                'status' => 502,
                'message' => 'Supabase Storage could not be reached. Please retry.',
            ];
        }

        return [
            'url' => $baseUrl . '/storage/v1/object/public/'
                . rawurlencode($bucket) . '/' . rawurlencode($objectName),
        ];
    }

    public function delete(string $diplomaUrl): ?array
    {
        $configuration = $this->configuration();
        if ($configuration['error']) {
            return $configuration['error'];
        }

        [$baseUrl, $serviceRoleKey, $bucket] = $configuration['values'];
        $baseHost = parse_url($baseUrl, PHP_URL_HOST);
        $imageHost = parse_url($diplomaUrl, PHP_URL_HOST);
        $imageScheme = parse_url($diplomaUrl, PHP_URL_SCHEME);
        $imagePath = parse_url($diplomaUrl, PHP_URL_PATH);
        $publicPrefix = '/storage/v1/object/public/' . $bucket . '/';

        if (
            !$baseHost
            || strtolower((string) $imageHost) !== strtolower((string) $baseHost)
            || strtolower((string) $imageScheme) !== 'https'
            || !is_string($imagePath)
            || !str_starts_with($imagePath, $publicPrefix)
        ) {
            return [
                'status' => 422,
                'message' => 'The diploma URL does not point to the configured public Supabase diploma bucket. The credential was not deleted.',
            ];
        }

        $objectPath = rawurldecode(substr($imagePath, strlen($publicPrefix)));
        $segments = explode('/', $objectPath);
        if (
            $objectPath === ''
            || in_array('.', $segments, true)
            || in_array('..', $segments, true)
        ) {
            return [
                'status' => 422,
                'message' => 'The diploma storage path is invalid. The credential was not deleted.',
            ];
        }

        $encodedPath = implode('/', array_map('rawurlencode', $segments));
        $endpoint = $baseUrl . '/storage/v1/object/'
            . rawurlencode($bucket) . '/' . $encodedPath;

        try {
            $response = Http::timeout(15)
                ->withHeaders($this->headers($serviceRoleKey))
                ->delete($endpoint);
        } catch (ConnectionException $exception) {
            Log::warning('Could not connect to Supabase Storage while deleting a diploma.', [
                'exception' => $exception->getMessage(),
            ]);

            return [
                'status' => 502,
                'message' => 'Supabase Storage could not be reached. The credential was not deleted; please retry.',
            ];
        }

        if ($response->status() === 404) {
            return null;
        }

        if (!$response->successful()) {
            return $this->httpError(
                'delete the diploma',
                $response->status(),
                true,
                $response->json('message'),
            );
        }

        return null;
    }

    private function configuration(): array
    {
        $baseUrl = rtrim((string) config('services.supabase.url'), '/');
        $serviceRoleKey = (string) config('services.supabase.service_role_key');
        $bucket = (string) config('services.supabase.diploma_bucket', 'diplomas');
        if ($baseUrl === '' || $serviceRoleKey === '' || $bucket === '') {
            return [
                'error' => [
                    'status' => 503,
                    'message' => 'Supabase Storage is not configured on the backend. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.',
                ],
            ];
        }

        return [
            'values' => [$baseUrl, $serviceRoleKey, $bucket],
            'error' => null,
        ];
    }

    private function headers(string $serviceRoleKey): array
    {
        $headers = [
            'apikey' => $serviceRoleKey,
        ];
        if (str_starts_with($serviceRoleKey, 'eyJ')) {
            $headers['Authorization'] = 'Bearer ' . $serviceRoleKey;
        }

        return $headers;
    }

    private function httpError(
        string $operation,
        int $status,
        bool $deleting = false,
        ?string $providerMessage = null,
    ): array
    {
        Log::warning('Supabase Storage rejected a diploma operation.', [
            'operation' => $operation,
            'status' => $status,
            'provider_message' => $providerMessage,
        ]);

        $detail = is_string($providerMessage) && trim($providerMessage) !== ''
            ? ' Supabase: ' . trim($providerMessage)
            : '';

        return [
            'status' => 502,
            'message' => 'Supabase Storage could not ' . $operation . ' (HTTP ' . $status . ').'
                . $detail
                . ($deleting ? ' The credential was not deleted; check the bucket and service key, then retry.' : ' Check the bucket and service key, then retry.'),
        ];
    }
}
