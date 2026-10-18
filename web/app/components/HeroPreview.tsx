"use client";

import { useRef } from "react";
import Image from "next/image";
import { householdCooks } from "./household";
import styles from "./HeroPreview.module.css";

export default function HeroPreview({ active, running, ready, onToggle, onReady }: { active: number; running: boolean; ready: boolean; onToggle: () => void; onReady: () => void }) {
  const loaded = useRef(new Set<number>());
  return <figure className={styles.preview} aria-label="Example household meal plan">
    <div className={styles.phone}>
      <div className={styles.screen}>
        {householdCooks.map((cook, index) => (index === 0 || ready) && <Image
          key={cook.name} className={styles.capture} data-active={active === index}
          src={cook.capture} width={1206} height={2622} sizes="(max-width: 760px) 280px, 326px"
          priority={index === 0} loading="eager"
          alt={`${cook.description}: ${cook.meal} in Plated’s Plan screen`}
          aria-hidden={active !== index}
          onLoad={() => { loaded.current.add(index); if (loaded.current.size === householdCooks.length) onReady(); }}
        />)}
        <span className={styles.island} aria-hidden="true" />
      </div>
    </div>
    <figcaption className={styles.caption}>
      <button onClick={onToggle} aria-label={running ? "Pause collaboration preview" : "Play collaboration preview"}>
        <svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{running ? <path d="M7 4v12m6-12v12" /> : <path d="m7 4 8 6-8 6Z" />}</svg>
        {running ? "Pause" : "Play"}
      </button>
    </figcaption>
  </figure>;
}
