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
    <AuthFrame eyebrow="Founder invitation" title="Choose a strong password" detail="Finish the invite before enrolling your authenticator.">
      <PasswordForm />
    </AuthFrame>
  );
}
