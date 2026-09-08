import { redirect } from "next/navigation";
import { getAdminAuthState } from "../../lib/admin/auth";
import AuthFrame, { AuthSetupState } from "../components/AuthFrame";
import LoginForm from "./LoginForm";

export default async function FounderLoginPage({ searchParams }: { searchParams: Promise<{ notice?: string }> }) {
  const params = await searchParams;
  const auth = await getAdminAuthState();
  if (auth.kind === "setup") return <AuthSetupState />;
  if (auth.kind === "ready") redirect("/admin");
  if (auth.kind === "mfa-required") redirect("/admin/mfa");

  return (
    <AuthFrame
      eyebrow="Founder console"
      title="Sign in to Plated"
      detail="Operational data and controls for the people responsible for Plated."
    >
      {params.notice === "link" ? <p role="alert">That invitation or recovery link is invalid or has expired.</p> : null}
      <LoginForm />
    </AuthFrame>
  );
}
