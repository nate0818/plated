"use client";

import { useMemo } from "react";
import styles from "./PlatedUp.module.css";

// The dish that lands on the plate. Picked once per mount, so it stays put
// through re-renders. Only things that sit on a plate: no bowls, no pans,
// nothing that already comes with its own dish drawn in.
const DISHES = ["🌮", "🌭", "🍔", "🍕", "🍗", "🥩", "🍖", "🥞", "🧇", "🥪", "🌯", "🍤", "🍳", "🥐"];
const BURST = ["🍅", "🧄", "🧅", "🥕", "🌽", "🍄", "🥦", "🫑", "🍋", "🥑", "🌶️", "🥬", "🧀", "🍤", "🔥", "🥄"];

type Bit = { glyph: string; dx: number; dy: number; rot: number; delay: number; size: number };

// Runs only after a real submit, so Math.random is fine here: nothing to
// hydrate against.
function scatter(count: number): Bit[] {
  return Array.from({ length: count }, (_, i) => {
    const angle = (-Math.PI / 2) + (Math.random() - 0.5) * Math.PI * 1.4;
    const dist = 110 + Math.random() * 220;
    return {
      glyph: BURST[i % BURST.length],
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist,
      rot: (Math.random() - 0.5) * 540,
      delay: Math.random() * 0.12,
      size: 18 + Math.random() * 16,
    };
  });
}

export default function PlatedUp() {
  const dish = useMemo(() => DISHES[Math.floor(Math.random() * DISHES.length)], []);
  const bits = useMemo(() => scatter(22), []);

  return (
    <div className={styles.stage} role="status" aria-live="polite">
      <div className={styles.burst} aria-hidden="true">
        {bits.map((b, i) => (
          <span
            key={i}
            className={styles.bit}
            style={
              {
                "--dx": `${b.dx}px`,
                "--dy": `${b.dy}px`,
                "--rot": `${b.rot}deg`,
                "--delay": `${b.delay}s`,
                fontSize: `${b.size}px`,
              } as React.CSSProperties
            }
          >
            {b.glyph}
          </span>
        ))}
      </div>

      <div className={styles.setting} aria-hidden="true">
        <span className={styles.fork}>🍴</span>
        <div className={styles.plate}>
          <span className={styles.dish}>{dish}</span>
        </div>
      </div>

      <div className={styles.words}>
        <p className={styles.title}>Plated.</p>
        <p className={styles.note}>
          You&rsquo;re on the list. One email when we&rsquo;re live.
        </p>
      </div>
    </div>
  );
}
