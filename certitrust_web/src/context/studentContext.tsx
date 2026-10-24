import { createContext, useContext, useState, ReactNode } from "react";
import { getSessionUser, verifyStudentId as verifyStudentIdApi } from "../services/authService";

type UserVerificationContextType = {
    isVerified: boolean;
    studentId: string;
    verificationError: string;
    verifyStudentId: (id: string) => Promise<boolean>;
    reset: () => void;
};

const UserVerificationContext = createContext<UserVerificationContextType | undefined>(undefined);

export default function UserVerificationProvider({ children }: { children: ReactNode }) {
    const [isVerified, setIsVerified] = useState<boolean>(false);
    const [studentId, setStudentId] = useState<string>("");
    const [verificationError, setVerificationError] = useState("");

    const verifyStudentId = async (id: string): Promise<boolean> => {
        const trimmed = id.trim();
        const email = getSessionUser()?.email;
        if (!trimmed || !email) {
            setVerificationError("Your session expired. Sign in again to verify your ID.");
            setIsVerified(false);
            return false;
        }

        try {
            await verifyStudentIdApi(email, trimmed);
            setIsVerified(true);
            setStudentId(trimmed);
            setVerificationError("");
            return true;
        } catch (error) {
            const message = (error as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setIsVerified(false);
            setVerificationError(message || "Student ID verification failed.");
            return false;
        }
    };

    const reset = () => {
        setIsVerified(false);
        setStudentId("");
        setVerificationError("");
    };

    return (
        <UserVerificationContext.Provider value={{ isVerified, studentId, verificationError, verifyStudentId, reset }}>
            {children}
        </UserVerificationContext.Provider>
    );
}

export function useUserVerification() {
    const context = useContext(UserVerificationContext);
    if (!context) {
        throw new Error("useStudentVerification must be used within a StudentVerificationProvider");
    }
    return context;
}