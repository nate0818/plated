"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import Field from "../components/Field";
import { createClient } from "../../lib/supabase/client";
import styles from "../admin.module.css";

export default function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");

    try {
      const supabase = createClient();
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (signInError) {
        setError(signInError.status === 429 ? "Too many attempts. Wait a moment and try again." : "That email and password were not accepted.");
        return;
      }

      const { data, error: assuranceError } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (assuranceError) {
        setError("Your account is signed in, but its security level could not be checked.");
        return;
      }

      router.replace(data.currentLevel === "aal2" ? "/admin" : "/admin/mfa");
      router.refresh();
    } catch {
      setError("The sign-in service could not be reached.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.authForm} onSubmit={signIn}>
      <Field
        label="Email"
        type="email"
        autoComplete="username"
        inputMode="email"
        required
        value={email}
        onChange={(event) => setEmail(event.target.value)}
      />
      <Field
        label="Password"
        type="password"
        autoComplete="current-password"
        required
        value={password}
        onChange={(event) => setPassword(event.target.value)}
      />
      {error ? <p className={styles.formError} role="alert">{error}</p> : null}
      <button className={styles.primaryButton} type="submit" disabled={busy || !email.trim() || !password}>
        {busy ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
