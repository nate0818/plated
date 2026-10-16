"use client";

import { useId, useRef, useState } from "react";
import AppShowcase from "./AppShowcase";
import { type AppScreen } from "./PhoneScreenshot";
import styles from "./ProductTour.module.css";

const steps: { screen: AppScreen; label: string; title: string; description: string; caption: string }[] = [
  { screen: "recipes", label: "Recipes", title: "Keep your favourites close.", description: "Save a recipe from a link or add your own. Your household gets one recipe book, ready whenever you’re planning dinner.", caption: "Your household’s recipe book" },
  { screen: "plan", label: "Plan", title: "Give dinner a place in the week.", description: "Pick a meal, choose a night, and assign a cook. Everyone can see what’s planned and who’s making it.", caption: "The plan, with a cook for each night" },
  { screen: "groceries", label: "Groceries", title: "Share the shopping, too.", description: "Add ingredients from your planned meals to Groceries. Keep the shopping in one shared list, whoever’s heading to the store.", caption: "Groceries for your planned meals" },
];

export default function ProductTour() {
  const [selected, setSelected] = useState(1);
  const panelId = useId();
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const current = steps[selected];

  return <div className={styles.tour}>
    <div className={styles.story}>
      <div className={styles.tabs} role="tablist" aria-label="Explore how Plated works" onKeyDown={event => {
        const directions: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1 };
        let next: number;
        if (event.key in directions) next = (selected + directions[event.key] + steps.length) % steps.length;
        else if (event.key === "Home") next = 0;
        else if (event.key === "End") next = steps.length - 1;
        else return;
        event.preventDefault();
        setSelected(next);
        tabs.current[next]?.focus();
      }}>
        {steps.map((step, index) => <button key={step.screen} ref={element => { tabs.current[index] = element; }} role="tab" id={`${panelId}-${index}`} aria-selected={index === selected} tabIndex={index === selected ? 0 : -1} aria-controls={panelId} onClick={() => setSelected(index)}>{step.label}</button>)}
      </div>
      <div className={styles.copy} id={panelId} role="tabpanel" aria-labelledby={`${panelId}-${selected}`} tabIndex={0}>
        <h3>{current.title}</h3>
        <p>{current.description}</p>
      </div>
    </div>
    <div className={styles.visual}>
      <div key={current.screen} className={styles.screenArrival}><AppShowcase screen={current.screen} compact /></div>
      <p className={styles.caption}>{current.caption}</p>
    </div>
  </div>;
}
