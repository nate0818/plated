"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import AppShowcase from "./AppShowcase";
import { type AppScreen } from "./PhoneScreenshot";
import styles from "./ProductTour.module.css";

const steps: { screen: AppScreen; label: string; title: string; description: string; caption: string }[] = [
  { screen: "plan", label: "Plan", title: "What’s for dinner. Who’s cooking.", description: "Choose a meal and assign a cook. Your whole household sees who’s making what, so organising dinner doesn’t always fall to the same person.", caption: "The meal, the night, and the person cooking" },
  { screen: "recipes", label: "Recipes", title: "Keep your favourites close.", description: "Add your own recipes, save one from a link, or keep a dish a friend shares at your Table. Your household’s recipe book grows with you.", caption: "Your household’s recipe book" },
  { screen: "groceries", label: "Groceries", title: "Share the shopping, too.", description: "Bring ingredients from your planned meals into one shared grocery list. Everyone knows what’s left to pick up.", caption: "Groceries for your planned meals" },
];

const cooks = [
  { name: "You", initial: "N", meal: "Salmon", night: "Tonight", image: "salmon", tone: "oat" },
  { name: "Sam", initial: "S", meal: "Pizza", night: "Tomorrow", image: "pizza", tone: "basil" },
  { name: "Riley", initial: "R", meal: "Steak", night: "Tuesday", image: "steak", tone: "mango" },
];

export default function ProductTour() {
  const [selected, setSelected] = useState(0);
  const [preload, setPreload] = useState(false);
  const sections = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 761px)");
    let observer: IntersectionObserver | undefined;
    function observe() {
      observer?.disconnect();
      if (!desktop.matches) return;
      observer = new IntersectionObserver(entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setPreload(true);
            const index = sections.current.indexOf(entry.target as HTMLElement);
            if (index !== -1) setSelected(index);
          }
        }
      }, { rootMargin: "-30% 0px -40% 0px", threshold: 0 });
      sections.current.forEach(section => { if (section) observer?.observe(section); });
    }
    observe();
    desktop.addEventListener("change", observe);
    return () => { observer?.disconnect(); desktop.removeEventListener("change", observe); };
  }, []);

  function goTo(index: number) {
    setSelected(index);
    sections.current[index]?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth", block: "center" });
  }

  return <div className={styles.tour}>
    <div className={styles.visual}>
      <nav className={styles.navigation} aria-label="Walkthrough steps">
        {steps.map((step, index) => <button key={step.screen} aria-current={selected === index ? "step" : undefined} onClick={() => goTo(index)}>{step.label}</button>)}
      </nav>
      <div className={styles.frame}>
        {steps.map((step, index) => <div key={step.screen} className={styles.screen} data-active={index === selected} aria-hidden={index !== selected} inert={index !== selected}><AppShowcase screen={step.screen} appearance="light" compact eager={preload} capture={step.screen === "plan" ? { src: "/app/plan-sam-light-818.png", alt: "Plated’s Plan screen showing Sam’s avatar, Pizza Night, and Sam is cooking" } : undefined} /></div>)}
      </div>
      <p className={styles.caption}>{steps[selected].screen === "plan" ? "Pizza Night. Sam’s cooking tomorrow." : steps[selected].caption}</p>
    </div>
    <div className={styles.story}>
      {steps.map((step, index) => <section key={step.screen} id={`tour-${step.screen}`} ref={element => { sections.current[index] = element; }} className={styles.step} data-active={selected === index} aria-labelledby={`tour-${step.screen}-title`}>
        <div className={styles.copy}>
          <p className={styles.stepLabel}><span>{String(index + 1).padStart(2, "0")}</span>{step.label}</p>
          <h3 id={`tour-${step.screen}-title`}>{step.title}</h3>
          <p className={styles.description}>{step.description}</p>
          {step.screen === "plan" && <ul className={styles.cooks} aria-label="Example household cooking nights">
            {cooks.map(cook => <li key={cook.name} className={styles.cook}>
              <span className={styles.avatar} data-theme="paper" data-tone={cook.tone} aria-hidden="true">
                {cook.initial}
                <span className={styles.mealBadge}><Image src={`/editorial/${cook.image}.webp`} alt="" width={40} height={40} sizes="40px" /></span>
              </span>
              <span className={styles.cookName}>{cook.name}</span>
              <span className={styles.cookMeal}>{cook.meal}<span>{cook.night}</span></span>
            </li>)}
          </ul>}
        </div>
        <div className={styles.mobileVisual}><AppShowcase screen={step.screen} appearance="light" compact capture={step.screen === "plan" ? { src: "/app/plan-sam-light-818.png", alt: "Plated’s Plan screen showing Sam’s avatar, Pizza Night, and Sam is cooking" } : undefined} /></div>
      </section>)}
    </div>
  </div>;
}
