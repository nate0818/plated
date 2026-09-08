"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "../../lib/supabase/client";
import Field from "../components/Field";
import styles from "../admin.module.css";

type Enrollment = { factorId: string; qrCode: string; secret: string };

export default function MfaForm({
  verifiedFactorId,
  lookupFailed = false,
  nextPath = "/admin",
  stepUp = false,
}: {
  verifiedFactorId: string | null;
  lookupFailed?: boolean;
  nextPath?: string;
  stepUp?: boolean;
}) {
  const router = useRouter();
  const [factorId, setFactorId] = useState(verifiedFactorId);
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<"" | "setup" | "verify" | "out">("");
  const [error, setError] = useState("");

  async function beginEnrollment() {
    if (busy) return;
    setBusy("setup");
    setError("");
    try {
      const supabase = createClient();
      const { data: factors, error: factorsError } = await supabase.auth.mfa.listFactors();
      if (factorsError) throw factorsError;
      for (const factor of factors?.totp ?? []) {
        if (factor.status !== "verified") {
          const { error: removeError } = await supabase.auth.mfa.unenroll({ factorId: factor.id });
          if (removeError) throw removeError;
        }
      }
      const { data, error: enrollError } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "Plated",
      });
      if (enrollError) {
        setError("An authenticator could not be enrolled. Try again.");
        return;
      }
      setFactorId(data.id);
      setEnrollment({ factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret });
    } catch {
      setError("The authentication service could not be reached.");
    } finally {
      setBusy("");
    }
  }

  async function verify(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !factorId || code.length !== 6) return;
    setBusy("verify");
    setError("");
    try {
      const supabase = createClient();
      const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
      if (verifyError) {
        setError("That code was not accepted. Wait for a new code and try again.");
        return;
      }
      router.replace(nextPath);
      router.refresh();
    } catch {
      setError("The authentication service could not be reached.");
    } finally {
      setBusy("");
    }
  }

  async function signOut() {
    if (busy) return;
    setBusy("out");
    setError("");
    try {
      const { error: signOutError } = await createClient().auth.signOut({ scope: "local" });
      if (signOutError) {
        setError("The session could not be cleared. Try again.");
        return;
      }
      router.replace("/admin/login");
      router.refresh();
    } catch {
      setError("The authentication service could not be reached.");
    } finally {
      setBusy("");
    }
  }

  if (lookupFailed) {
    return (
      <div className={styles.authForm}>
        <p className={styles.formError} role="alert">{error || "Your authenticator enrollment could not be checked. Try signing in again."}</p>
        <button className={styles.textButton} type="button" onClick={signOut} disabled={Boolean(busy)}>Use another account</button>
      </div>
    );
  }

  if (!factorId) {
    return (
      <div className={styles.authForm}>
        <div className={styles.callout}>
          <p className={styles.calloutTitle}>{stepUp ? "Authenticator setup required" : "First sign-in"}</p>
          <p className={styles.smallMuted}>Use 1Password, Apple Passwords, Authy, or another TOTP authenticator. You will scan a QR code, then enter its six-digit code.</p>
        </div>
        {error ? <p className={styles.formError} role="alert">{error}</p> : null}
        <button className={styles.primaryButton} type="button" onClick={beginEnrollment} disabled={Boolean(busy)}>
          {busy === "setup" ? "Preparing…" : "Set up authenticator"}
        </button>
        <button className={styles.textButton} type="button" onClick={signOut} disabled={Boolean(busy)}>Use another account</button>
      </div>
    );
  }

  return (
    <form className={styles.authForm} onSubmit={verify}>
      {enrollment ? (
        <div className={styles.enrollment}>
          <Image className={styles.qrCode} src={enrollment.qrCode} alt="Authenticator enrollment QR code" width={208} height={208} unoptimized />
          <p className={styles.smallMuted}>Can&apos;t scan it? Enter this key:</p>
          <code className={styles.secret}>{enrollment.secret}</code>
        </div>
      ) : null}
      <Field
        label="Six-digit code"
        className={styles.codeInput}
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9]{6}"
        maxLength={6}
        required
        autoFocus={!enrollment}
        value={code}
        onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
      />
      {error ? <p className={styles.formError} role="alert">{error}</p> : null}
      <button className={styles.primaryButton} type="submit" disabled={Boolean(busy) || code.length !== 6}>
        {busy === "verify" ? "Verifying…" : stepUp ? "Confirm and continue" : "Open console"}
      </button>
      <button className={styles.textButton} type="button" onClick={signOut} disabled={Boolean(busy)}>Use another account</button>
    </form>
  );
}
