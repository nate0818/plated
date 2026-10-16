"use client";

import Image from "next/image";
import { useId, useRef, useState } from "react";
import { type AppScreen, screenDescriptions, screenImages } from "./PhoneScreenshot";
import styles from "./AppShowcase.module.css";

const screens: { screen: AppScreen; label: string }[] = [
  { screen: "plan", label: "Plan" },
  { screen: "recipes", label: "Recipes" },
  { screen: "groceries", label: "Groceries" },
  { screen: "table", label: "Table" },
];

export default function AppShowcase({ screen = "plan", priority = false, compact = false, featured = false }: { screen?: AppScreen; priority?: boolean; compact?: boolean; featured?: boolean }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [selected, setSelected] = useState(0);
  const current = screens[selected];

  function open(index: number) {
    setSelected(index);
    dialog.current?.showModal();
  }

  return <>
    <div className={`${styles.preview} ${compact ? styles.compact : ""} ${featured ? styles.featured : ""}`}>
      <button className={styles.screenButton} onClick={() => open(screens.findIndex(item => item.screen === screen))} aria-label={`Enlarge Plated’s ${screens.find(item => item.screen === screen)?.label} screen`} aria-haspopup="dialog">
        <span className={styles.capture}>
          <Image src={featured ? "/app/editorial-recipes-light-current.png" : screenImages[screen]} alt={featured ? "Plated’s recipe book in Light appearance, with saved recipes and food photography" : screenDescriptions[screen]} width={1206} height={2622} sizes="(max-width: 760px) 280px, 320px" priority={priority} loading={priority ? "eager" : "lazy"} />
        </span>
      </button>
    </div>

    <dialog
      ref={dialog}
      className={styles.dialog}
      aria-labelledby={titleId}
      onClick={event => { if (event.target === event.currentTarget) dialog.current?.close(); }}
      onKeyDown={event => {
        if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
          event.preventDefault();
          setSelected(value => (value + (event.key === "ArrowRight" ? 1 : -1) + screens.length) % screens.length);
        }
      }}
    >
      <div className={styles.dialogContent}>
        <div className={styles.dialogHeader}>
          <div><h2 id={titleId}>{current.label}</h2><p>Plated app preview</p></div>
          <button className={styles.close} onClick={() => dialog.current?.close()} aria-label="Close app preview"><svg viewBox="0 0 20 20" width="20" height="20" stroke="currentColor" strokeWidth="1.4" aria-hidden="true"><path d="m5 5 10 10M15 5 5 15" /></svg></button>
        </div>
        <div className={styles.screenControls} aria-label="Choose an app screen">
          {screens.map((item, index) => <button key={item.screen} aria-pressed={index === selected} onClick={() => setSelected(index)}>{item.label}</button>)}
        </div>
        <div className={styles.fullScreen}>
          <Image src={featured && current.screen === "recipes" ? "/app/editorial-recipes-light-current.png" : screenImages[current.screen]} alt={featured && current.screen === "recipes" ? "Plated’s recipe book in Light appearance" : screenDescriptions[current.screen]} width={1206} height={2622} sizes="300px" />
        </div>
        <p className={styles.dialogNote} aria-live="polite">{current.label} screen, {selected + 1} of {screens.length}</p>
      </div>
    </dialog>
  </>;
}
