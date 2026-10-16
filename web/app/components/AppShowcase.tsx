"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { type AppScreen, screenDescriptions, screenImages } from "./PhoneScreenshot";
import styles from "./AppShowcase.module.css";

const screens: { screen: AppScreen; label: string }[] = [
  { screen: "recipes", label: "Recipes" },
  { screen: "plan", label: "Plan" },
  { screen: "groceries", label: "Groceries" },
  { screen: "table", label: "Table" },
];
const steps = [
  { title: "Save what you love.", description: "Your own recipes and the ones you find, together in a cookbook that feels like yours." },
  { title: "Share the thinking.", description: "Give the week a little shape. Choose a meal, pick a night, and see who’s cooking." },
  { title: "Shop from the plan.", description: "Bring your planned meals into Groceries and keep the list with the people who need it." },
];

export default function AppShowcase() {
  const dialog = useRef<HTMLDialogElement>(null);
  const [selected, setSelected] = useState(0);
  const current = screens[selected];

  function open(index: number) {
    setSelected(index);
    dialog.current?.showModal();
  }

  return <>
    <div className={styles.steps}>
      {steps.map((step, index) => <article key={step.title} className={styles.step}>
        <div className={styles.stepLabel}><span>0{index + 1}</span><span>{screens[index].label}</span></div>
        <h3>{step.title}</h3>
        <p>{step.description}</p>
        <button className={styles.preview} onClick={() => open(index)} aria-label={`View full ${screens[index].label} screen`}>
          <div className={styles.screenCrop}><Image src={screenImages[screens[index].screen]} alt={screenDescriptions[screens[index].screen]} width={800} height={1739} sizes="(max-width: 760px) 280px, 300px" /></div>
          <span className={styles.viewLabel}>View full screen <span aria-hidden="true">↗</span></span>
        </button>
      </article>)}
    </div>
    <p className={styles.previewNote}>A look inside the real app. <button onClick={() => open(3)}>Explore all four screens <span aria-hidden="true">↗</span></button></p>
    <dialog ref={dialog} className={styles.dialog} aria-labelledby="app-preview-title" onClick={event => { if (event.target === event.currentTarget) dialog.current?.close(); }} onKeyDown={event => {
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        setSelected(value => (value + (event.key === "ArrowRight" ? 1 : -1) + screens.length) % screens.length);
      }
    }}>
      <div className={styles.dialogContent}>
        <div className={styles.dialogHeader}><div><p>Inside Plated</p><h2 id="app-preview-title">{current.label}</h2></div><button className={styles.close} onClick={() => dialog.current?.close()} aria-label="Close app preview">✕</button></div>
        <div className={styles.screenControls} aria-label="Choose an app screen">{screens.map((item, index) => <button key={item.screen} aria-pressed={index === selected} onClick={() => setSelected(index)}>{item.label}</button>)}</div>
        <div className={styles.fullScreen}><Image src={screenImages[current.screen]} alt={screenDescriptions[current.screen]} width={800} height={1739} sizes="320px" /></div>
        <p className={styles.dialogNote} aria-live="polite">{current.label} · Actual Plated app capture · {selected + 1} of {screens.length}</p>
      </div>
    </dialog>
  </>;
}
