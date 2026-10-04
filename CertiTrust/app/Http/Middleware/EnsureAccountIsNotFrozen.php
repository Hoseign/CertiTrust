<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureAccountIsNotFrozen
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user && $user->isAccessFrozen()) {
            $isAccessStateRequest = $request->isMethod('GET')
                && $request->is('api/user');
            $isFrozenChatRead = $request->isMethod('GET')
                && ($request->is('api/chat/contacts') || $request->is('api/chat/messages'));
            $isFrozenChatSend = $request->isMethod('POST')
                && $request->is('api/chat/messages');

            if ($isAccessStateRequest || $isFrozenChatRead || $isFrozenChatSend) {
                return $next($request);
            }

            return response()->json([
                'status' => 'error',
                'message' => 'This account is frozen. Only support chat with the administrator who applied the freeze is available.',
            ], 423);
        }

        return $next($request);
    }
}
