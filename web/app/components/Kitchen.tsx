"use client";

import { useState } from "react";
import styles from "./Kitchen.module.css";
import Ketchup from "./Ketchup";

// Each tap plates a dish and the kitchen has an opinion about it. The list
// is walked in order so the jokes land in sequence, and after the last one
// the kitchen closes and stays closed until the page is reloaded.
const ORDERS: { dish: string; line: string }[] = [
  { dish: "🌮", line: "Taco. Tuesday was two days ago, but fine." },
  { dish: "🍕", line: "Pizza. The kitchen respects your honesty." },
  { dish: "🥞", line: "Pancakes. At this hour. We won't tell." },
  { dish: "🍔", line: "Burger. You have tapped this plate three times. Are you hungry?" },
  { dish: "🥗", line: "Salad. Balance. Very mature." },
  { dish: "🍗", line: "Chicken. The chef says that's the last one." },
  { dish: "🥐", line: "Croissant. Fine. One more, because it's flaky." },
  { dish: "🧇", line: "Waffle. Okay, that's genuinely enough." },
];

const CLOSED = "The kitchen is closed. Go home and plan a real dinner.";

export default function Kitchen() {
  const [count, setCount] = useState(0);
  const [stamp, setStamp] = useState(0); // restarts the landing animation

  const closed = count >= ORDERS.length;
  const current = count > 0 ? ORDERS[Math.min(count, ORDERS.length) - 1] : null;

  function tap() {
    if (closed) return;
    setCount((c) => c + 1);
    setStamp((s) => s + 1);
  }

  return (
    <div className={styles.kitchen}>
      <button
        type="button"
        className={`${styles.plate} ${closed ? styles.plateClosed : ""}`}
        onClick={tap}
        aria-label={closed ? "The kitchen is closed" : current ? `${current.line} Tap to plate another.` : "Page not found. Tap the plate to order something."}
        disabled={closed}
      >
        <span className={styles.dishWell} aria-hidden="true">
          {current ? (
            <span key={stamp} className={styles.dish}>
              {closed ? "🧽" : current.dish}
            </span>
          ) : (
            <span className={styles.code}>
              <Ketchup />
            </span>
          )}
        </span>
      </button>

    </div>
  );
}
