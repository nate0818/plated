"use client";

import Image from "next/image";
import { useId, useRef, useState } from "react";
import { type AppScreen, lightScreenImages, screenDescriptions, screenImages } from "./PhoneScreenshot";
import styles from "./AppShowcase.module.css";

const screens: { screen: AppScreen; label: string }[] = [
  { screen: "plan", label: "Plan" },
  { screen: "recipes", label: "Recipes" },
  { screen: "groceries", label: "Groceries" },
  { screen: "table", label: "Table" },
];

export default function AppShowcase({ screen = "plan", priority = false, eager = false, compact = false, appearance = "editorial", capture }: { screen?: AppScreen; priority?: boolean; eager?: boolean; compact?: boolean; appearance?: "editorial" | "light"; capture?: { src: string; alt: string } }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [selected, setSelected] = useState(0);
  const current = screens[selected];
  const imageFor = (name: AppScreen) => name === screen && capture ? capture.src : appearance === "light" ? lightScreenImages[name] ?? screenImages[name] : screenImages[name];
  const descriptionFor = (name: AppScreen) => name === screen && capture ? capture.alt : screenDescriptions[name];

  function open(index: number) {
    setSelected(index);
    dialog.current?.showModal();
  }

  return <>
    <div className={`${styles.preview} ${compact ? styles.compact : ""}`}>
      <button className={styles.screenButton} onClick={() => open(screens.findIndex(item => item.screen === screen))} aria-label={`Enlarge Plated’s ${screens.find(item => item.screen === screen)?.label} screen`} aria-haspopup="dialog">
        <span className={styles.capture}>
          <span className={styles.deviceScreen}><Image src={imageFor(screen)} alt={descriptionFor(screen)} width={1206} height={2622} sizes="(max-width: 760px) 280px, 320px" priority={priority} loading={priority || eager ? "eager" : "lazy"} /><span className={styles.island} aria-hidden="true" /></span>
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
          <Image src={imageFor(current.screen)} alt={descriptionFor(current.screen)} width={1206} height={2622} sizes="300px" /><span className={styles.island} aria-hidden="true" />
        </div>
        <p className={styles.dialogNote} aria-live="polite">{current.label} screen, {selected + 1} of {screens.length}</p>
      </div>
    </dialog>
  </>;
}
