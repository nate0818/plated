"use client";

import { useId, useState } from "react";
import styles from "./WaitlistForm.module.css";

type Phase = "idle" | "sending" | "done" | "failed";

// Three states, never one: sending (no words, just the disabled button),
// saved (the confirmation), could not save (say so, offer the retry). The
// form never claims an address was kept unless the server said it was.
export default function WaitlistForm({ compact = false }: { compact?: boolean }) {
  const inputId = useId();
  const errorId = `${inputId}-error`;
  const [email, setEmail] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [message, setMessage] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (phase === "sending") return;
    setPhase("sending");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const body = (await res.json().catch(() => ({}))) as { error?: string };
      if (!res.ok) {
        setMessage(body.error ?? "That didn't save. Try again.");
        setPhase("failed");
        return;
      }
      setPhase("done");
    } catch {
      setMessage("Couldn't reach the server. Try again.");
      setPhase("failed");
    }
  }

  if (phase === "done") {
    return <div className={styles.done} role="status"><p className={styles.successTitle}>You&rsquo;re on the list.</p><p>We&rsquo;ll email you when Plated launches.</p></div>;
  }

  return (
    <form className={`${styles.form} ${compact ? styles.compact : ""}`} onSubmit={submit}>
      <label className={styles.srOnly} htmlFor={inputId}>
        Email address
      </label>
      <div className={styles.row}>
        <input
          id={inputId}
          className={styles.input}
          type="email"
          name="email"
          inputMode="email"
          autoComplete="email"
          placeholder="you@example.com"
          required
          value={email}
          onChange={(e) => {
            setEmail(e.target.value);
            if (phase === "failed") setPhase("idle");
          }}
          aria-invalid={phase === "failed" || undefined}
          aria-describedby={phase === "failed" ? errorId : undefined}
        />
        <button className={styles.button} type="submit" disabled={phase === "sending"} aria-busy={phase === "sending"}>
          {phase === "sending" ? "Saving" : "Join the waitlist"}
        </button>
      </div>
      {phase === "failed" ? (
        <p id={errorId} className={styles.error} role="alert">
          {message}
        </p>
      ) : (
        <p className={styles.note}>One email when we launch. That&rsquo;s all.</p>
      )}
    </form>
  );
}
