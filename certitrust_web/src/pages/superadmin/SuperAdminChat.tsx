import { useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { useChat } from "../../hooks/useChat";
import { deleteChatMessage, sendChatMessage } from "../../services/chatApi";
import { getSessionUser } from "../../services/authService";

type Message = {
    id: string;
    from: "me" | "them";
    text: string;
    status?: "Delivered" | "Sent";
};

type Chat = {
    name: string;
    lastActive: string;
    messages: Message[];
};

function StatusIcon({ status }: { status: "Delivered" | "Sent" }) {
    return (
        <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
        >
            {status === "Delivered" ? (
                <>
                    <polyline points="1 13 6 18 16 6" />
                    <polyline points="9 15 11 17 22 5" />
                </>
            ) : (
                <polyline points="5 13 10 18 20 6" />
            )}
        </svg>
    );
}

export default function SuperAdminChat() {
    const { id } = useParams<{ id: string }>();
    const navigate = useNavigate();
    const [text, setText] = useState("");
    const [menuMsgId, setMenuMsgId] = useState<string | null>(null);
    const [isSending, setIsSending] = useState(false);
    const bottomRef = useRef<HTMLDivElement | null>(null);
    const sessionUser = getSessionUser();
    const contactId = id ? Number(id) : undefined;
    const { messages: apiMessages, contacts, loading, error, refresh } = useChat(contactId);
    const contact = contacts.find((item) => String(item.id) === id);
    const messages: Message[] = apiMessages.map((message) => ({
        id: String(message.id),
        from: message.user_id === sessionUser?.id ? "me" : "them",
        text: message.message,
        status: message.delivered_at ? "Delivered" : message.user_id === sessionUser?.id ? "Sent" : undefined,
    }));
    const chat: Chat | undefined = contact ? {
        name: String(contact.name || contact.email || "Contact"),
        lastActive: contact.last_seen_at ? new Date(String(contact.last_seen_at)).toLocaleString() : "",
        messages,
    } : undefined;

    useEffect(() => {
        bottomRef.current?.scrollIntoView({ behavior: "smooth" });
    }, [chat?.messages.length]);

    const send = async () => {
        const value = text.trim();
        if (!contactId || !chat || value === "" || isSending) return;
        setIsSending(true);
        try {
            await sendChatMessage({ message: value, recipientUserId: contactId });
            setText("");
            await refresh(true);
        } catch (sendError) {
            const message = (sendError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            window.alert(message || "Message could not be sent.");
        } finally {
            setIsSending(false);
        }
    };

    const deleteMessage = async (messageId: string, forEveryone: boolean) => {
        try {
            await deleteChatMessage(Number(messageId), forEveryone);
            setMenuMsgId(null);
            await refresh(true);
        } catch (deleteError) {
            const message = (deleteError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            window.alert(message || "Message could not be deleted.");
        }
    };

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">

            <SuperAdminSideBar />

            <main className="flex-1 min-w-0 h-screen flex flex-col">

                {loading && !chat ? (
                    <CertiTrustLoadingIndicator size={36} message="Loading conversation..." className="w-full p-10 text-gray-500" />
                ) : error ? (
                    <div role="alert" className="m-8 rounded-lg bg-red-50 p-4 text-sm text-red-700">{error}</div>
                ) : !chat ? (
                    <div className="p-10 text-center text-gray-500">
                        Conversation not found.
                    </div>
                ) : (
                    <>
                        {/* HEADER */}
                        <div className="px-6 md:px-10 py-5 border-b border-gray-200 bg-[#F5F7FB]">
                            <div className="max-w-3xl mx-auto flex items-center gap-5">

                                <button
                                    type="button"
                                    aria-label="Back to messages"
                                    onClick={() => navigate("/superadmin/ask")}
                                    className="p-2 rounded-lg text-[#0A192F] hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg
                                        width="28"
                                        height="28"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <line x1="20" y1="12" x2="4" y2="12" />
                                        <polyline points="10 6 4 12 10 18" />
                                    </svg>
                                </button>

                                <div className="flex-1 min-w-0">
                                    <h1 className="text-3xl font-normal text-[#0A192F] leading-tight truncate">
                                        {chat.name}
                                    </h1>

                                    <p className="text-[15px] text-[#0A192F]">
                                        Last active: {chat.lastActive}
                                    </p>
                                </div>

                                <button
                                    type="button"
                                    aria-label="Conversation options"
                                    className="p-2 rounded-lg text-[#0A192F] hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor">
                                        <circle cx="5" cy="12" r="2" />
                                        <circle cx="12" cy="12" r="2" />
                                        <circle cx="19" cy="12" r="2" />
                                    </svg>
                                </button>

                                <button
                                    type="button"
                                    aria-label="More actions"
                                    className="p-2 rounded-lg text-[#0A192F] hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor">
                                        <circle cx="12" cy="5" r="2" />
                                        <circle cx="12" cy="12" r="2" />
                                        <circle cx="12" cy="19" r="2" />
                                    </svg>
                                </button>

                            </div>
                        </div>

                        {/* MESSAGES */}
                        <div className="flex-1 min-h-0 overflow-y-auto px-6 md:px-10 py-8">
                            <div className="max-w-3xl mx-auto flex flex-col gap-5">

                                {chat.messages.map((m) => {
                                    const mine = m.from === "me";

                                    return (
                                        <div
                                            key={m.id}
                                            className={`max-w-[75%] px-6 pt-5 pb-4 rounded-3xl ${mine
                                                    ? "self-end bg-[#003366] text-white rounded-br-md"
                                                    : "self-start bg-white text-[#0A192F] border border-gray-200 rounded-bl-md"
                                                }`}
                                        >

                                            <div className="flex items-center justify-between gap-6 mb-3">
                                                <span className="font-bold text-lg">
                                                    {mine ? "You" : chat.name}
                                                </span>

                                                <div className="relative">

                                                    <button
                                                        type="button"
                                                        aria-label="Message options"
                                                        aria-haspopup="menu"
                                                        aria-expanded={menuMsgId === m.id}
                                                        onClick={() =>
                                                            setMenuMsgId(menuMsgId === m.id ? null : m.id)
                                                        }
                                                        className={`p-1 rounded-lg transition-colors ${mine
                                                                ? "hover:bg-white/10"
                                                                : "hover:bg-gray-100"
                                                            }`}
                                                    >
                                                        <svg
                                                            width="22"
                                                            height="22"
                                                            viewBox="0 0 24 24"
                                                            fill="currentColor"
                                                        >
                                                            <circle cx="12" cy="5" r="2" />
                                                            <circle cx="12" cy="12" r="2" />
                                                            <circle cx="12" cy="19" r="2" />
                                                        </svg>
                                                    </button>

                                                    {menuMsgId === m.id && (
                                                        <>
                                                            <div
                                                                className="fixed inset-0 z-10"
                                                                onClick={() => setMenuMsgId(null)}
                                                            />

                                                            <div
                                                                role="menu"
                                                                className="absolute right-0 top-full mt-1 z-20 w-56 bg-white text-[#0A192F] rounded-xl border border-gray-200 shadow-xl py-2"
                                                            >
                                                                <button
                                                                    type="button"
                                                                    role="menuitem"
                                                                    onClick={() => deleteMessage(m.id, false)}
                                                                    className="w-full text-left px-5 py-3 text-base font-medium hover:bg-gray-50 transition-colors"
                                                                >
                                                                    Delete for me
                                                                </button>

                                                                {mine && (
                                                                    <button
                                                                        type="button"
                                                                        role="menuitem"
                                                                        onClick={() => deleteMessage(m.id, true)}
                                                                        className="w-full text-left px-5 py-3 text-base font-medium text-red-600 hover:bg-gray-50 transition-colors"
                                                                    >
                                                                        Delete for everyone
                                                                    </button>
                                                                )}
                                                            </div>
                                                        </>
                                                    )}

                                                </div>
                                            </div>

                                            <p className="text-lg leading-7 break-words">
                                                {m.text}
                                            </p>

                                            {m.status && (
                                                <p className="flex items-center justify-end gap-2 text-[15px] text-white/80 mt-2">
                                                    <StatusIcon status={m.status} />
                                                    {m.status}
                                                </p>
                                            )}

                                        </div>
                                    );
                                })}

                                <div ref={bottomRef} />

                            </div>
                        </div>

                        {/* INPUT */}
                        <div className="px-6 md:px-10 py-5 border-t border-gray-200 bg-[#F5F7FB]">
                            <div className="max-w-3xl mx-auto flex items-center gap-4">

                                <button
                                    type="button"
                                    aria-label="Attach file"
                                    className="p-2 rounded-lg text-[#333F4F] hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg
                                        width="30"
                                        height="30"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M21.4 11.1l-9.2 9.2a6 6 0 0 1-8.5-8.5l9.2-9.2a4 4 0 0 1 5.7 5.7l-9.2 9.2a2 2 0 0 1-2.8-2.8l8.5-8.5" />
                                    </svg>
                                </button>

                                <input
                                    type="text"
                                    value={text}
                                    onChange={(e) => setText(e.target.value)}
                                    onKeyDown={(e) => {
                                        if (e.key === "Enter") send();
                                    }}
                                    placeholder="Type your message..."
                                    className="flex-1 min-w-0 bg-white rounded-xl border-2 border-[#0A3A6B] px-5 py-4 text-lg text-[#0A192F] placeholder-gray-500 outline-none"
                                />

                                <button
                                    type="button"
                                    aria-label="Send message"
                                    onClick={() => void send()}
                                    disabled={isSending || !text.trim()}
                                    className="p-2 rounded-lg text-[#333F4F] hover:bg-gray-200/70 transition-colors shrink-0 disabled:opacity-50"
                                >
                                    <svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M2 21l21-9L2 3v7l15 2-15 2z" />
                                    </svg>
                                </button>

                            </div>
                        </div>
                    </>
                )}

            </main>

        </div>
    );
}