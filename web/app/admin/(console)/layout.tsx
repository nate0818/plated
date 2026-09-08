import { redirect } from "next/navigation";
import { adminUserLabel, getAdminAuthState } from "../../lib/admin/auth";
import AdminShell from "../components/AdminShell";

export default async function ConsoleLayout({ children }: { children: React.ReactNode }) {
  const auth = await getAdminAuthState();
  if (auth.kind === "setup" || auth.kind === "signed-out") redirect("/admin/login");
  if (auth.kind === "mfa-required") redirect("/admin/mfa");

  return <AdminShell userLabel={adminUserLabel(auth.user)}>{children}</AdminShell>;
}
