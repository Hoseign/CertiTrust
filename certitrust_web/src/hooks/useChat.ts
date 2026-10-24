import { useCallback, useEffect, useRef, useState } from "react";
import { listChatContacts, listChatMessages, type ChatMessage } from "../services/chatApi";

export function useChat(withUserId?: number) {
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [contacts, setContacts] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const refreshing = useRef(false);
    const refreshQueued = useRef(false);
    const queuedContacts = useRef(false);
    const lastContactsRefresh = useRef(0);

    const refresh = useCallback(async (silent = false, includeContacts = true) => {
        if (refreshing.current) {
            refreshQueued.current = true;
            queuedContacts.current ||= includeContacts;
            return;
        }
        refreshing.current = true;
        if (!silent) setLoading(true);
        try {
            const [nextMessages, nextContacts] = await Promise.all([
                listChatMessages(withUserId),
                includeContacts ? listChatContacts() : Promise.resolve(null),
            ]);
            setMessages(nextMessages);
            if (nextContacts) {
                setContacts(nextContacts);
                lastContactsRefresh.current = Date.now();
            }
            setError("");
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load messages.");
        } finally {
            refreshing.current = false;
            if (!silent) setLoading(false);
            if (refreshQueued.current) {
                const shouldRefreshContacts = queuedContacts.current;
                refreshQueued.current = false;
                queuedContacts.current = false;
                window.setTimeout(() => void refresh(true, shouldRefreshContacts), 0);
            }
        }
    }, [withUserId]);

    useEffect(() => {
        void refresh();
        lastContactsRefresh.current = Date.now();
        const refreshWhenVisible = () => {
            if (document.visibilityState === "visible") {
                const includeContacts = Date.now() - lastContactsRefresh.current >= 30000;
                void refresh(true, includeContacts);
            }
        };
        const timer = window.setInterval(refreshWhenVisible, 3000);
        document.addEventListener("visibilitychange", refreshWhenVisible);
        return () => {
            window.clearInterval(timer);
            document.removeEventListener("visibilitychange", refreshWhenVisible);
        };
    }, [refresh]);

    return { messages, contacts, loading, error, refresh };
}