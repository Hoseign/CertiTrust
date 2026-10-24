import { useEffect, useState } from "react";
import { listChatContacts, listChatMessages, type ChatMessage } from "../services/chatApi";

export function useChat(withUserId?: number) {
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [contacts, setContacts] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");

    const refresh = async (silent = false) => {
        if (!silent) setLoading(true);
        try {
            const [nextMessages, nextContacts] = await Promise.all([
                listChatMessages(withUserId),
                listChatContacts(),
            ]);
            setMessages(nextMessages);
            setContacts(nextContacts);
            setError("");
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load messages.");
        } finally {
            if (!silent) setLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, [withUserId]);

    return { messages, contacts, loading, error, refresh };
}