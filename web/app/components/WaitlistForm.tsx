"use client";

import { useId, useState } from "react";
import Link from "next/link";
import styles from "./WaitlistForm.module.css";

type Phase = "idle" | "sending" | "done" | "failed";

// Three states, never one: sending (a progress label and disabled button),
// saved (the confirmation), could not save (say so, offer the retry). The
// form never claims an address was kept unless the server said it was.
export default function WaitlistForm({ compact = false, intent = "launch" }: { compact?: boolean; intent?: "launch" | "early-access" }) {
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
        body: JSON.stringify({ email, intent }),
      });
      const body = (await res.json().catch(() => ({}))) as { error?: string };
      if (!res.ok) {
        setMessage(body.error ?? "We couldn’t send your request. Please try again.");
        setPhase("failed");
        return;
      }
      setPhase("done");
    } catch {
      setMessage("We couldn’t send your request. Please try again.");
      setPhase("failed");
    }
  }

  if (phase === "done") {
    return <div className={styles.done} role="status"><span className={styles.successIcon} aria-hidden="true">✓</span><p className={styles.successTitle}>{intent === "early-access" ? "Request received" : "You’re on the list"}</p><p>{intent === "early-access" ? "We’ll email you when an invitation is available." : "We’ll email you when Plated launches."}</p></div>;
  }

  return (
    <form className={`${styles.form} ${compact ? styles.compact : ""}`} onSubmit={submit}>
      <label className={styles.label} htmlFor={inputId}>
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
          maxLength={254}
          autoCapitalize="none"
          spellCheck={false}
          value={email}
          onChange={(e) => {
            setEmail(e.target.value);
            if (phase === "failed") setPhase("idle");
          }}
          aria-invalid={phase === "failed" || undefined}
          aria-describedby={phase === "failed" ? errorId : undefined}
        />
        <button className={styles.button} type="submit" disabled={phase === "sending"} aria-busy={phase === "sending"}>
          {phase === "sending" ? "Sending your request…" : intent === "early-access" ? "Request early access" : "Join the waitlist"}
        </button>
      </div>
      {phase === "failed" ? (
        <p id={errorId} className={styles.error} role="alert">
          {message}
        </p>
      ) : (
        <p className={styles.note}>{intent === "early-access" ? "We’ll only email you about early access." : "We’ll only email you when Plated launches."} <Link href="/privacy">Privacy</Link></p>
      )}
    </form>
  );
}
