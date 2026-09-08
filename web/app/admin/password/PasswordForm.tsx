"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "../../lib/supabase/client";
import Field from "../components/Field";
import styles from "../admin.module.css";

export default function PasswordForm() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    if (password.length < 14) {
      setError("Use at least 14 characters.");
      return;
    }
    if (password !== confirmation) {
      setError("The passwords do not match.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const { error: updateError } = await createClient().auth.updateUser({ password });
      if (updateError) {
        setError("The password could not be saved. Open a fresh invitation link and try again.");
        return;
      }
      router.replace("/admin/mfa");
      router.refresh();
    } catch {
      setError("The authentication service could not be reached.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.authForm} onSubmit={save}>
      <Field label="New password" type="password" minLength={14} autoComplete="new-password" required value={password} onChange={(event) => setPassword(event.target.value)} />
      <Field label="Repeat password" type="password" minLength={14} autoComplete="new-password" required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} />
      {error ? <p className={styles.formError} role="alert">{error}</p> : null}
      <button className={styles.primaryButton} type="submit" disabled={busy || password.length < 14 || confirmation.length < 14}>{busy ? "Saving…" : "Save and continue"}</button>
    </form>
  );
}
