"use client";

import styles from "./PlatedUp.module.css";

// Only things that sit on a plate: no bowls, no pans, nothing that already
// comes with its own dish drawn in.
const DISHES = ["🌮", "🌭", "🍔", "🍕", "🍗", "🥩", "🍖", "🥞", "🧇", "🥪", "🌯", "🍤", "🍳", "🥐"];
const BURST = ["🍅", "🧄", "🧅", "🥕", "🌽", "🍄", "🥦", "🫑", "🍋", "🥑", "🌶️", "🥬", "🧀", "🍤", "🔥", "🥄"];

type Bit = { glyph: string; dx: number; dy: number; rot: number; delay: number; size: number };

// A deterministic little noise function keeps the celebration stable across
// hydration and re-renders. The scene still feels scattered; React just never
// has to reconcile two different celebrations for the same saved address.
function noise(index: number): number {
  const value = Math.sin(index * 12.9898 + 78.233) * 43758.5453;
  return value - Math.floor(value);
}

function scatter(count: number): Bit[] {
  return Array.from({ length: count }, (_, i) => {
    const angle = (-Math.PI / 2) + (noise(i * 5 + 1) - 0.5) * Math.PI * 1.4;
    const dist = 110 + noise(i * 5 + 2) * 220;
    return {
      glyph: BURST[i % BURST.length],
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist,
      rot: (noise(i * 5 + 3) - 0.5) * 540,
      delay: noise(i * 5 + 4) * 0.12,
      size: 18 + noise(i * 5 + 5) * 16,
    };
  });
}

export default function PlatedUp() {
  const dish = DISHES[Math.floor(noise(97) * DISHES.length)];
  const bits = scatter(22);

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
