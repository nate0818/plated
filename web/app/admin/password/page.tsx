import { redirect } from "next/navigation";
import { getAdminAuthState } from "../../lib/admin/auth";
import AuthFrame, { AuthSetupState } from "../components/AuthFrame";
import PasswordForm from "./PasswordForm";

export default async function FounderPasswordPage() {
  const auth = await getAdminAuthState();
  if (auth.kind === "setup") return <AuthSetupState />;
  if (auth.kind === "signed-out") redirect("/admin/login");
  if (auth.kind === "ready") redirect("/admin");

  return (
    <AuthFrame title="Choose a password" detail="Next you will add an authenticator app.">
      <PasswordForm />
    </AuthFrame>
  );
}
