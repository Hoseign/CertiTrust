import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import Sidebar from "./Sidebar";
import StudentSidebar from "./StudentSidebar";
import CertiTrustLoadingIndicator from "./CertiTrustLoadingIndicator";
import { useChat } from "../hooks/useChat";
import {
    clearChatConversation,
    deleteChatMessage,
    sendChatMessage,
    type ChatMessage,
} from "../services/chatApi";
import { getSessionUser } from "../services/authService";

type ChatWorkspaceProps = {
    isAdmin: boolean;
};

function field(record: Record<string, unknown>, key: string, fallback = "") {
    const value = record[key];
    return typeof value === "string" || typeof value === "number"
        ? String(value)
        : fallback;
}

function initials(name: string) {
    return name
        .split(/\s+/)
        .map((part) => part[0])
        .filter(Boolean)
        .slice(0, 2)
        .join("")
        .toUpperCase();
}

function repliedMessage(message: ChatMessage) {
    const reply = message.reply_to;
    return reply && typeof reply === "object" && !Array.isArray(reply)
        ? reply as Record<string, unknown>
        : null;
}

export default function ChatWorkspace({ isAdmin }: ChatWorkspaceProps) {
    const [searchParams, setSearchParams] = useSearchParams();
    const requestedId = Number(searchParams.get("with_user_id"));
    const [selectedId, setSelectedId] = useState<number | undefined>(
        Number.isFinite(requestedId) && requestedId > 0 ? requestedId : undefined,
    );
    const [query, setQuery] = useState("");
    const [draft, setDraft] = useState("");
    const [attachment, setAttachment] = useState<File | undefined>();
    const [replyTo, setReplyTo] = useState<ChatMessage | null>(null);
    const [isSending, setIsSending] = useState(false);
    const [actionError, setActionError] = useState("");
    const [profileContact, setProfileContact] = useState<Record<string, unknown> | null>(null);
    const scrollRef = useRef<HTMLDivElement>(null);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const sessionUser = getSessionUser();
    const { messages, contacts, loading, error, refresh } = useChat(selectedId);

    useEffect(() => {
        const nextId = Number.isFinite(requestedId) && requestedId > 0
            ? requestedId
            : undefined;
        setSelectedId(nextId);
    }, [requestedId]);

    useEffect(() => {
        scrollRef.current?.scrollTo({
            top: scrollRef.current.scrollHeight,
            behavior: "smooth",
        });
    }, [messages, isSending]);

    const selectedContact = contacts.find(
        (contact) => Number(contact.id) === selectedId,
    );
    const filteredContacts = useMemo(() => {
        const normalizedQuery = query.trim().toLowerCase();
        if (!normalizedQuery) return contacts;
        return contacts.filter((contact) => [
            field(contact, "name"),
            field(contact, "email"),
            field(contact, "role_label"),
            field(contact, "student_id"),
            field(contact, "last_message_preview"),
        ].some((value) => value.toLowerCase().includes(normalizedQuery)));
    }, [contacts, query]);

    const openContact = (contact: Record<string, unknown>) => {
        const id = Number(contact.id);
        if (!Number.isFinite(id) || id <= 0) return;
        setSelectedId(id);
        setDraft("");
        setAttachment(undefined);
        setReplyTo(null);
        setActionError("");
        setSearchParams({ with_user_id: String(id) });
    };

    const closeConversation = () => {
        setSelectedId(undefined);
        setDraft("");
        setAttachment(undefined);
        setReplyTo(null);
        setActionError("");
        setSearchParams({});
    };

    const send = async () => {
        const text = draft.trim();
        if ((!text && !attachment) || !selectedId || isSending) return;
        setIsSending(true);
        setActionError("");
        try {
            await sendChatMessage({
                message: text,
                recipientUserId: selectedId,
                attachment,
                replyToId: replyTo?.id,
            });
            setDraft("");
            setAttachment(undefined);
            setReplyTo(null);
            if (fileInputRef.current) fileInputRef.current.value = "";
            await refresh(true);
        } catch (sendError) {
            setActionError(
                (sendError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "Message could not be sent.",
            );
        } finally {
            setIsSending(false);
        }
    };

    const removeMessage = async (message: ChatMessage, forEveryone: boolean) => {
        setActionError("");
        try {
            await deleteChatMessage(message.id, forEveryone);
            await refresh(true);
        } catch (deleteError) {
            setActionError(
                (deleteError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "Message could not be deleted.",
            );
        }
    };

    const clearConversation = async (forEveryone: boolean) => {
        if (!selectedId || !window.confirm(
            forEveryone
                ? "Clear this conversation for both people?"
                : "Clear this conversation from your inbox?",
        )) return;
        setActionError("");
        try {
            await clearChatConversation(selectedId, forEveryone);
            await refresh(true);
        } catch (clearError) {
            setActionError(
                (clearError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "The conversation could not be cleared.",
            );
        }
    };

    const heading = isAdmin ? "AnsQ" : "AskQ";
    const showContactList = !selectedId;

    return (
        <div className="min-h-screen bg-[#F6F8FC] md:grid md:grid-cols-[286px_minmax(0,1fr)]">
            {isAdmin ? <Sidebar /> : <StudentSidebar />}
            <main className="flex h-screen min-h-[560px] min-w-0 flex-col p-3 sm:p-5 md:p-7">
                <header className="mb-4 flex shrink-0 items-center gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
                    <button
                        type="button"
                        data-toggle-sidebar
                        aria-label="Open navigation"
                        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-200 md:hidden"
                    >
                        ☰
                    </button>
                    {selectedContact && !showContactList && (
                        <button
                            type="button"
                            onClick={closeConversation}
                            aria-label="Back to conversations"
                            className="h-10 w-10 shrink-0 rounded-xl border border-slate-200 text-lg md:hidden"
                        >
                            ←
                        </button>
                    )}
                    <div className="min-w-0 flex-1">
                        <p className="m-0 text-xs font-extrabold uppercase tracking-wider text-blue-700">
                            {heading} · Conversations
                        </p>
                        <h1 className="mt-1 truncate text-xl font-extrabold text-[#0A192F] sm:text-2xl">
                            {selectedContact
                                ? field(selectedContact, "name", field(selectedContact, "email", "Conversation"))
                                : "Messages"}
                        </h1>
                        {selectedContact && (
                            <p className="mt-1 truncate text-xs text-slate-500">
                                {field(selectedContact, "last_seen_label",
                                    selectedContact.is_active === true ? "Online" : "Last active: unknown")}
                            </p>
                        )}
                    </div>
                    {selectedContact && (
                        <button
                            type="button"
                            onClick={() => setProfileContact(selectedContact)}
                            className="hidden rounded-lg border border-slate-200 px-3 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50 sm:block"
                        >
                            Contact profile
                        </button>
                    )}
                </header>

                {error && <p role="alert" className="mb-3 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                {actionError && <p role="alert" className="mb-3 rounded-lg bg-red-50 p-3 text-sm text-red-700">{actionError}</p>}

                <section className="flex min-h-0 flex-1 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
                    <aside className={`${showContactList ? "flex" : "hidden"} w-full shrink-0 flex-col border-r border-slate-200 md:flex md:w-80 lg:w-96`}>
                        <div className="border-b border-slate-100 p-4">
                            <label className="sr-only" htmlFor="conversation-search">Search conversations</label>
                            <input
                                id="conversation-search"
                                type="search"
                                value={query}
                                onChange={(event) => setQuery(event.target.value)}
                                placeholder="Search people or conversations"
                                className="w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-blue-600 focus:ring-4 focus:ring-blue-600/10"
                            />
                        </div>
                        <div className="min-h-0 flex-1 overflow-y-auto">
                            {loading && contacts.length === 0 ? (
                                <CertiTrustLoadingIndicator size={28} message="Loading conversations..." className="w-full p-5 text-sm text-slate-500" />
                            ) : filteredContacts.length === 0 ? (
                                <p className="p-5 text-sm text-slate-500">
                                    {query.trim() ? "No matching contacts." : "No conversations yet."}
                                </p>
                            ) : filteredContacts.map((contact) => {
                                const id = Number(contact.id);
                                const name = field(contact, "name", field(contact, "email", "Contact"));
                                const unread = Number(contact.unread_count) || 0;
                                return (
                                    <button
                                        type="button"
                                        key={String(contact.id)}
                                        onClick={() => openContact(contact)}
                                        className={`flex w-full items-center gap-3 border-b border-slate-100 px-4 py-3 text-left transition hover:bg-slate-50 ${selectedId === id ? "bg-blue-50" : ""}`}
                                    >
                                        <span className="relative flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-full bg-blue-50 font-bold text-blue-700">
                                            {field(contact, "profile_image_url")
                                                ? <img src={field(contact, "profile_image_url")} alt="" className="h-full w-full object-cover" />
                                                : initials(name)}
                                            {contact.is_active === true && <span className="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-white bg-green-500" />}
                                        </span>
                                        <span className="min-w-0 flex-1">
                                            <span className="flex items-center justify-between gap-2">
                                                <span className="truncate text-sm font-bold text-slate-900">{name}</span>
                                                {unread > 0 && <span className="rounded-full bg-blue-700 px-2 py-0.5 text-xs font-bold text-white">{unread}</span>}
                                            </span>
                                            <span className="block truncate text-xs text-slate-500">{field(contact, "role_label", "Contact")}</span>
                                            <span className="mt-1 block truncate text-xs text-slate-500">
                                                {contact.last_message_from_me === true ? "You: " : ""}
                                                {field(contact, "last_message_preview", "No messages yet")}
                                            </span>
                                        </span>
                                    </button>
                                );
                            })}
                        </div>
                    </aside>

                    <div className={`${showContactList ? "hidden md:flex" : "flex"} min-w-0 flex-1 flex-col`}>
                        {!selectedContact ? (
                            <div className="hidden flex-1 flex-col items-center justify-center p-8 text-center md:flex">
                                <div className="text-4xl text-blue-700">◈</div>
                                <h2 className="mt-3 text-lg font-bold text-slate-800">Select a conversation</h2>
                                <p className="mt-1 text-sm text-slate-500">Choose a contact to view messages and continue the conversation.</p>
                            </div>
                        ) : (
                            <>
                                <div className="flex shrink-0 items-center justify-between gap-3 border-b border-slate-100 px-4 py-3">
                                    <button
                                        type="button"
                                        onClick={() => setProfileContact(selectedContact)}
                                        className="truncate text-left text-sm font-bold text-slate-800 hover:text-blue-700"
                                    >
                                        {field(selectedContact, "role_label", "Contact")}
                                        {field(selectedContact, "student_id") && ` · Student ID: ${field(selectedContact, "student_id")}`}
                                    </button>
                                    <div className="flex shrink-0 gap-2">
                                        <button type="button" onClick={() => void clearConversation(false)} className="rounded-lg border border-slate-200 px-2.5 py-1.5 text-xs font-semibold text-slate-600 hover:bg-slate-50">Clear for me</button>
                                        <button type="button" onClick={() => void clearConversation(true)} className="hidden rounded-lg border border-slate-200 px-2.5 py-1.5 text-xs font-semibold text-slate-600 hover:bg-slate-50 sm:block">Clear for everyone</button>
                                    </div>
                                </div>

                                <div ref={scrollRef} className="min-h-0 flex-1 space-y-3 overflow-y-auto p-4 sm:p-5">
                                    {loading && messages.length === 0 ? (
                                        <CertiTrustLoadingIndicator size={24} message="Loading messages..." className="w-full text-sm text-slate-500" />
                                    ) : messages.length === 0 ? (
                                        <div className="flex h-full min-h-40 flex-col items-center justify-center text-center">
                                            <p className="font-semibold text-slate-700">No messages yet</p>
                                            <p className="mt-1 text-sm text-slate-500">Send a message to start chatting.</p>
                                        </div>
                                    ) : messages.map((message) => {
                                        const own = Number(message.user_id) === sessionUser?.id;
                                        const reply = repliedMessage(message);
                                        const sender = field(message, "sender_name", own ? "You" : "Contact");
                                        const attachmentUrl = message.attachment_url;
                                        return (
                                            <div key={message.id} className={`flex ${own ? "justify-end" : "justify-start"}`}>
                                                <article className={`max-w-[88%] min-w-0 rounded-2xl px-3.5 py-3 sm:max-w-[75%] ${own ? "rounded-br-sm bg-blue-700 text-white" : "rounded-bl-sm bg-slate-100 text-slate-900"}`}>
                                                    <div className="mb-1 flex items-center justify-between gap-4">
                                                        <span className="text-xs font-bold opacity-80">{sender}</span>
                                                        <details className="group relative">
                                                            <summary className="cursor-pointer list-none rounded px-1 font-bold opacity-70 hover:opacity-100" aria-label="Message actions">···</summary>
                                                            <div className="absolute right-0 z-10 mt-1 grid min-w-40 gap-1 rounded-lg border border-slate-200 bg-white p-1 text-xs text-slate-700 shadow-lg">
                                                                <button type="button" onClick={() => setReplyTo(message)} className="rounded px-2 py-1.5 text-left hover:bg-slate-100">Reply</button>
                                                                <button type="button" onClick={() => void removeMessage(message, false)} className="rounded px-2 py-1.5 text-left hover:bg-slate-100">Delete for me</button>
                                                                <button type="button" onClick={() => void removeMessage(message, true)} className="rounded px-2 py-1.5 text-left hover:bg-slate-100">Delete for everyone</button>
                                                            </div>
                                                        </details>
                                                    </div>
                                                    {reply && (
                                                        <div className={`mb-2 border-l-2 pl-2 text-xs opacity-80 ${own ? "border-white/60" : "border-blue-500"}`}>
                                                            <p className="font-bold">{field(reply, "sender_name", "Reply")}</p>
                                                            <p className="line-clamp-2">{field(reply, "message")}</p>
                                                        </div>
                                                    )}
                                                    {message.message && <p className="whitespace-pre-wrap break-words text-sm">{message.message}</p>}
                                                    {attachmentUrl && (
                                                        <a href={attachmentUrl} target="_blank" rel="noreferrer" className="mt-2 block underline">
                                                            {message.attachment_type === "video"
                                                                ? <video src={attachmentUrl} controls className="max-h-64 max-w-full rounded-lg" />
                                                                : <img src={attachmentUrl} alt="Message attachment" className="max-h-64 max-w-full rounded-lg object-contain" />}
                                                        </a>
                                                    )}
                                                    {message.is_report === true && <p className="mt-2 text-xs font-bold">Report</p>}
                                                    <div className="mt-1 flex justify-end gap-2 text-[10px] opacity-70">
                                                        <time dateTime={message.created_at}>{new Date(message.created_at).toLocaleString()}</time>
                                                        {own && <span>{message.delivered_at ? "Delivered" : "Sent"}</span>}
                                                    </div>
                                                </article>
                                            </div>
                                        );
                                    })}
                                </div>

                                <form
                                    className="shrink-0 border-t border-slate-100 p-3 sm:p-4"
                                    onSubmit={(event) => {
                                        event.preventDefault();
                                        void send();
                                    }}
                                >
                                    {replyTo && (
                                        <div className="mb-2 flex items-center justify-between gap-2 rounded-lg border-l-2 border-blue-600 bg-blue-50 px-3 py-2 text-xs text-slate-700">
                                            <span className="truncate">Replying to {field(replyTo, "sender_name", "message")}: {replyTo.message}</span>
                                            <button type="button" onClick={() => setReplyTo(null)} aria-label="Cancel reply" className="font-bold">×</button>
                                        </div>
                                    )}
                                    {attachment && (
                                        <div className="mb-2 flex items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2 text-xs">
                                            <span className="truncate">{attachment.name}</span>
                                            <button type="button" onClick={() => {
                                                setAttachment(undefined);
                                                if (fileInputRef.current) fileInputRef.current.value = "";
                                            }} aria-label="Remove attachment" className="font-bold text-red-700">Remove</button>
                                        </div>
                                    )}
                                    <div className="flex items-end gap-2">
                                        <button
                                            type="button"
                                            onClick={() => fileInputRef.current?.click()}
                                            aria-label="Attach image or video"
                                            className="h-11 shrink-0 rounded-xl border border-slate-200 px-3 text-lg text-slate-600 hover:bg-slate-50"
                                        >
                                            +
                                        </button>
                                        <input
                                            ref={fileInputRef}
                                            type="file"
                                            accept="image/jpeg,image/png,image/gif,video/mp4,video/quicktime,video/webm"
                                            className="hidden"
                                            onChange={(event) => setAttachment(event.target.files?.[0])}
                                        />
                                        <textarea
                                            value={draft}
                                            onChange={(event) => setDraft(event.target.value)}
                                            onKeyDown={(event) => {
                                                if (event.key === "Enter" && !event.shiftKey) {
                                                    event.preventDefault();
                                                    void send();
                                                }
                                            }}
                                            placeholder="Type your message..."
                                            rows={1}
                                            className="min-h-11 min-w-0 flex-1 resize-y rounded-xl border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-blue-600 focus:ring-4 focus:ring-blue-600/10"
                                        />
                                        <button
                                            type="submit"
                                            disabled={isSending || (!draft.trim() && !attachment)}
                                            className="h-11 shrink-0 rounded-xl bg-blue-700 px-4 text-sm font-bold text-white hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50"
                                        >
                                            {isSending ? "Sending..." : "Send"}
                                        </button>
                                    </div>
                                </form>
                            </>
                        )}
                    </div>
                </section>
            </main>

            {profileContact && (
                <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/50 p-4" onClick={() => setProfileContact(null)}>
                    <section role="dialog" aria-modal="true" aria-label="Contact profile" className="w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl" onClick={(event) => event.stopPropagation()}>
                        <div className="flex items-center gap-3">
                            {field(profileContact, "profile_image_url")
                                ? <img src={field(profileContact, "profile_image_url")} alt="" className="h-14 w-14 rounded-full object-cover" />
                                : <div className="flex h-14 w-14 items-center justify-center rounded-full bg-blue-50 font-bold text-blue-700">{initials(field(profileContact, "name", "Contact"))}</div>}
                            <div className="min-w-0">
                                <h2 className="truncate font-bold text-slate-900">{field(profileContact, "name", "Contact")}</h2>
                                <p className="text-sm text-slate-500">{field(profileContact, "role_label", "Contact")}</p>
                            </div>
                        </div>
                        <dl className="mt-4 space-y-2 break-words text-sm">
                            <div><dt className="inline font-semibold">Email: </dt><dd className="inline">{field(profileContact, "email", "Not available")}</dd></div>
                            {field(profileContact, "student_id") && <div><dt className="inline font-semibold">Student ID: </dt><dd className="inline">{field(profileContact, "student_id")}</dd></div>}
                            <div><dt className="inline font-semibold">Status: </dt><dd className="inline">{profileContact.is_active === true ? "Online" : field(profileContact, "last_seen_label", "Offline")}</dd></div>
                        </dl>
                        <button type="button" onClick={() => setProfileContact(null)} className="mt-5 w-full rounded-xl bg-slate-900 px-4 py-2.5 font-bold text-white">Close</button>
                    </section>
                </div>
            )}
        </div>
    );
}
