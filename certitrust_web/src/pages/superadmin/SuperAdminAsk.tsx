import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { useChat } from "../../hooks/useChat";
import { getSessionUser } from "../../services/authService";

type Conversation = {
    id: string;
    name: string;
    subtitle: string;
    extra?: string;
    preview: string;
    lastActive: string;
    unread?: number;
    type: "school" | "student";
    avatarText?: string;
    avatarBg?: string;
    avatarColor?: string;
    avatarSrc?: string; // optional: put the school logo path here, e.g. "/ucu.png"
};

export default function SuperAdminAsk() {
    const [search, setSearch] = useState("");
    const navigate = useNavigate();
    const sessionUser = getSessionUser();
    const { messages, contacts, loading, error } = useChat();

    const conversations: Conversation[] = contacts.map((contact) => {
        const id = String(contact.id);
        const lastMessage = messages
            .filter((message) => String(message.user_id) === id || String(message.recipient_user_id) === id)
            .at(-1);
        const isSchool = String(contact.role_label || "").toLowerCase().includes("school");
        return {
            id,
            name: String(contact.name || contact.email || "Contact"),
            subtitle: String(contact.role_label || "Conversation"),
            extra: contact.student_id ? `Student ID: ${String(contact.student_id)}` : undefined,
            preview: lastMessage
                ? `${Number(lastMessage.user_id) === sessionUser?.id ? "You: " : ""}${lastMessage.message || "Attachment"}`
                : "No messages yet",
            lastActive: contact.last_seen_at ? `Last active: ${new Date(String(contact.last_seen_at)).toLocaleString()}` : "",
            type: isSchool ? "school" : "student",
            avatarText: String(contact.university_code || contact.name || "CT").slice(0, 3).toUpperCase(),
            avatarBg: "#DCE8FA",
            avatarColor: "#0A3A6B",
        };
    });

    const filtered = useMemo(() => {
        const q = search.trim().toLowerCase();

        if (q === "") return conversations;

        return conversations.filter((c) =>
            [c.name, c.subtitle, c.extra ?? "", c.preview]
                .join(" ")
                .toLowerCase()
                .includes(q)
        );
    }, [search, conversations]);

    return (
        <div className="min-h-screen bg-[#F5F7FB] flex">

            {/* SIDEBAR */}
            <SuperAdminSideBar />

            {/* MAIN CONTENT */}
            <main className="flex-1 h-screen overflow-y-auto min-w-0 p-6 md:p-10">

                <div className="max-w-3xl mx-auto">

                    {/* HEADER */}
                    <h1 className="text-3xl font-extrabold text-[#0A192F] mb-8">
                        Messages
                    </h1>
                    {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}

                    {/* SEARCH */}
                    <div className="relative mb-6">
                        <span className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-600">
                            <svg
                                width="24"
                                height="24"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2.2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <circle cx="11" cy="11" r="7" />
                                <line x1="21" y1="21" x2="16.65" y2="16.65" />
                            </svg>
                        </span>

                        <input
                            type="text"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            placeholder="Search people or credentials"
                            className="w-full pl-14 pr-4 py-4 bg-white rounded-xl border border-gray-400 text-[#0A192F] placeholder-gray-500 outline-none focus:border-[#0A3A6B] focus:ring-2 focus:ring-blue-100 transition-all"
                        />
                    </div>

                    {/* CONVERSATIONS */}
                    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">

                        {loading && contacts.length === 0 ? <CertiTrustLoadingIndicator size={28} message="Loading conversations..." className="w-full p-6 text-sm text-slate-500" /> : filtered.map((c, index) => (
                            <div
                                key={c.id}
                                role="link"
                                tabIndex={0}
                                onClick={() => navigate(`/superadmin/ask/${c.id}`)}
                                onKeyDown={(e) => {
                                    if (e.key === "Enter") navigate(`/superadmin/ask/${c.id}`);
                                }}
                                className={`flex items-center gap-5 px-6 py-6 hover:bg-gray-50 transition-colors cursor-pointer ${index !== filtered.length - 1
                                    ? "border-b border-gray-200"
                                    : ""
                                    }`}
                            >

                                {/* AVATAR */}
                                <div
                                    className="w-14 h-14 rounded-full shrink-0 flex items-center justify-center overflow-hidden"
                                    style={{
                                        backgroundColor:
                                            c.type === "student" ? "#DCE8FA" : c.avatarBg,
                                        color:
                                            c.type === "student" ? "#0A3A6B" : c.avatarColor,
                                    }}
                                >
                                    {c.avatarSrc ? (
                                        <img
                                            src={c.avatarSrc}
                                            alt={c.name}
                                            className="w-full h-full object-cover"
                                        />
                                    ) : c.type === "student" ? (
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
                                            <path d="M4 12a8 8 0 0 1 16 0v1a7 7 0 0 1-7 7h-2a7 7 0 0 1-7-7v-1z" />
                                            <circle cx="9" cy="13" r="0.6" fill="currentColor" />
                                            <circle cx="15" cy="13" r="0.6" fill="currentColor" />
                                        </svg>
                                    ) : (
                                        <span className="text-sm font-extrabold">
                                            {c.avatarText}
                                        </span>
                                    )}
                                </div>

                                {/* TEXT */}
                                <div className="flex-1 min-w-0">

                                    <p className="text-lg font-semibold text-[#0A192F] truncate">
                                        {c.name}
                                    </p>

                                    <p className="text-[15px] text-gray-600 mt-0.5">
                                        {c.subtitle}
                                    </p>

                                    {c.extra && (
                                        <p className="text-[15px] text-gray-600">
                                            {c.extra}
                                        </p>
                                    )}

                                    <p
                                        className={`text-[15px] truncate ${c.unread
                                            ? "font-bold text-[#0A192F]"
                                            : "text-gray-400"
                                            }`}
                                    >
                                        {c.preview}
                                    </p>

                                    <p className="text-sm text-gray-400 mt-0.5">
                                        {c.lastActive}
                                    </p>

                                </div>

                                {/* UNREAD */}
                                {c.unread ? (
                                    <span className="w-8 h-8 rounded-full bg-[#0A3A6B] text-white text-sm font-bold flex items-center justify-center shrink-0">
                                        {c.unread}
                                    </span>
                                ) : null}

                                {/* MENU */}
                                <button
                                    type="button"
                                    aria-label="More options"
                                    onClick={(e) => e.stopPropagation()}
                                    onKeyDown={(e) => e.stopPropagation()}
                                    className="p-2 rounded-lg text-gray-600 hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor">
                                        <circle cx="5" cy="12" r="2" />
                                        <circle cx="12" cy="12" r="2" />
                                        <circle cx="19" cy="12" r="2" />
                                    </svg>
                                </button>

                            </div>
                        ))}

                        {filtered.length === 0 && (
                            <div className="px-6 py-10 text-center text-gray-500">
                                No results found.
                            </div>
                        )}

                    </div>

                </div>

            </main>
        </div>
    );
}