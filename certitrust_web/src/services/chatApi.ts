import { apiClient } from "./apiClient";

export type ChatMessage = {
    id: number;
    user_id: number;
    recipient_user_id: number;
    sender_name: string;
    message: string;
    attachment_url?: string | null;
    attachment_type?: string | null;
    created_at: string;
    [field: string]: unknown;
};

export async function listChatMessages(withUserId?: number) {
    const { data } = await apiClient.get<{ data: ChatMessage[] }>("/chat/messages", {
        params: withUserId ? { with_user_id: withUserId } : undefined,
    });
    return data.data;
}

export async function listChatContacts(search?: string) {
    const { data } = await apiClient.get<{ data: Record<string, unknown>[] }>("/chat/contacts", {
        params: search ? { search } : undefined,
    });
    return data.data;
}

export async function listChatPresence() {
    const { data } = await apiClient.get<{ data: Record<string, unknown>[] }>("/chat/presence");
    return data.data;
}

export async function sendChatMessage(payload: {
    message: string;
    recipientUserId: number;
    attachment?: File;
    replyToId?: number;
    isReport?: boolean;
}) {
    const form = new FormData();
    form.append("message", payload.message);
    form.append("recipient_user_id", String(payload.recipientUserId));
    if (payload.replyToId) form.append("reply_to_id", String(payload.replyToId));
    if (payload.isReport) form.append("is_report", "1");
    if (payload.attachment) form.append("attachment", payload.attachment);
    const { data } = await apiClient.post<{ data: ChatMessage }>("/chat/messages", form);
    return data.data;
}

export async function deleteChatMessage(messageId: number, forEveryone = false) {
    const { data } = await apiClient.delete(`/chat/messages/${messageId}`, {
        params: { mode: forEveryone ? "everyone" : "me" },
    });
    return data;
}

export async function clearChatConversation(userId: number, forEveryone = false) {
    const { data } = await apiClient.delete(`/chat/conversation/${userId}`, {
        params: { mode: forEveryone ? "everyone" : "me" },
    });
    return data;
}