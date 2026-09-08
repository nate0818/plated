import { redirect } from "next/navigation";
import { getAdminAuthState, safeAdminNextPath } from "../../lib/admin/auth";
import { createClient } from "../../lib/supabase/server";
import AuthFrame, { AuthSetupState } from "../components/AuthFrame";
import MfaForm from "./MfaForm";

export default async function FounderMfaPage({
  searchParams,
}: {
  searchParams: Promise<{ stepup?: string; next?: string }>;
}) {
  const params = await searchParams;
  const stepUp = params.stepup === "1";
  const nextPath = safeAdminNextPath(stepUp ? params.next : undefined);
  const auth = await getAdminAuthState();
  if (auth.kind === "setup") return <AuthSetupState />;
  if (auth.kind === "signed-out") redirect("/admin/login");
  if (auth.kind === "ready" && (!stepUp || auth.recentTotp)) redirect(stepUp ? nextPath : "/admin");

  const supabase = await createClient();
  const { data, error } = await supabase.auth.mfa.listFactors();
  const verifiedFactor = data?.totp.find((factor) => factor.status === "verified") ?? null;

  return (
    <AuthFrame
      title={stepUp ? "Confirm it’s you" : verifiedFactor ? "Enter your code" : "Set up two-step verification"}
      detail={verifiedFactor || stepUp
        ? "Use the current code from your authenticator app."
        : "Add an authenticator app to finish signing in."}
    >
      <MfaForm
        verifiedFactorId={verifiedFactor?.id ?? null}
        lookupFailed={Boolean(error)}
        nextPath={nextPath}
        stepUp={stepUp}
      />
    </AuthFrame>
  );
}
