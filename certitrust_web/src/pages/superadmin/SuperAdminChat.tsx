import { useParams } from "react-router-dom";
import ChatWorkspace from "@/Components/Organisms/ChatWorkspace";

export default function SuperAdminChat() {
    const { id } = useParams<{ id: string }>();
    const parsedId = Number(id);

    return (
        <ChatWorkspace
            isAdmin
            isSuperAdmin
            initialContactId={Number.isFinite(parsedId) && parsedId > 0 ? parsedId : undefined}
        />
    );
}
