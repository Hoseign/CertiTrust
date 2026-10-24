import { useCallback, useEffect, useRef, useState } from "react";
import { listChatContacts, listChatMessages, type ChatMessage } from "../services/chatApi";

export function useChat(withUserId?: number) {
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [contacts, setContacts] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const refreshing = useRef(false);

    const refresh = useCallback(async (silent = false) => {
        if (refreshing.current) return;
        refreshing.current = true;
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
            refreshing.current = false;
            if (!silent) setLoading(false);
        }
    }, [withUserId]);

    useEffect(() => {
        void refresh();
        const refreshWhenVisible = () => {
            if (document.visibilityState === "visible") void refresh(true);
        };
        const timer = window.setInterval(refreshWhenVisible, 5000);
        document.addEventListener("visibilitychange", refreshWhenVisible);
        return () => {
            window.clearInterval(timer);
            document.removeEventListener("visibilitychange", refreshWhenVisible);
        };
    }, [refresh]);

    return { messages, contacts, loading, error, refresh };
}