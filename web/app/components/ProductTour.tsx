"use client";

import { useEffect, useRef, useState } from "react";
import HouseholdCooks from "./HouseholdCooks";
import AppShowcase from "./AppShowcase";
import { type AppScreen } from "./PhoneScreenshot";
import styles from "./ProductTour.module.css";

const steps: { screen: AppScreen; label: string; title: string; description: string; caption: string }[] = [
  { screen: "plan", label: "Plan", title: "See what’s for dinner and who’s cooking", description: "Choose a meal, pick a night, and assign a cook. Everyone can see the plan, so you can share the work of dinner.", caption: "Your household’s meal plan" },
  { screen: "recipes", label: "Recipes", title: "Keep your favorites close", description: "Add a recipe yourself, save one from a link, or save one a friend shares at your Table. Keep them all in your household’s recipe book.", caption: "Your household’s recipe book" },
  { screen: "groceries", label: "Groceries", title: "One grocery list for everyone", description: "Add ingredients from planned meals to a shared list. Anyone in your household can see what’s still needed.", caption: "A grocery list everyone can use" },
];

export default function ProductTour() {
  const [selected, setSelected] = useState(0);
  const [preload, setPreload] = useState(false);
  const sections = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 1024px) and (min-height: 720px)");
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
      }, { rootMargin: "-35% 0px -50% 0px", threshold: 0 });
      sections.current.forEach(section => { if (section) observer?.observe(section); });
    }
    observe();
    desktop.addEventListener("change", observe);
    return () => { observer?.disconnect(); desktop.removeEventListener("change", observe); };
  }, []);

  function goTo(index: number) {
    sections.current[index]?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth", block: "start" });
  }

  return <div className={styles.tour}>
    <div className={styles.visual}>
      <nav className={styles.navigation} aria-label="Walkthrough steps">
        {steps.map((step, index) => <button key={step.screen} aria-current={selected === index ? "step" : undefined} onClick={() => goTo(index)}>{step.label}</button>)}
      </nav>
      <div className={styles.frame}>
        {steps.map((step, index) => <div key={step.screen} className={styles.screen} data-active={index === selected} aria-hidden={index !== selected} inert={index !== selected}><AppShowcase screen={step.screen} appearance="light" compact eager={preload} capture={step.screen === "plan" ? { src: "/app/plan-sam-light-818.png", alt: "Plated’s Plan screen showing Sam’s avatar, Pizza Night, and Sam is cooking" } : undefined} /></div>)}
      </div>
      <p className={styles.caption}>{steps[selected].screen === "plan" ? "Sam’s making pizza tomorrow" : steps[selected].caption}</p>
    </div>
    <div className={styles.story}>
      {steps.map((step, index) => <section key={step.screen} id={`tour-${step.screen}`} ref={element => { sections.current[index] = element; }} className={styles.step} data-active={selected === index} aria-labelledby={`tour-${step.screen}-title`}>
        <div className={styles.copy}>
          <p className={styles.stepLabel}><span>{String(index + 1).padStart(2, "0")}</span>{step.label}</p>
          <h3 id={`tour-${step.screen}-title`}>{step.title}</h3>
          <p className={styles.description}>{step.description}</p>
          {step.screen === "plan" && <HouseholdCooks compact /> }
        </div>
        <div className={styles.mobileVisual}><AppShowcase screen={step.screen} appearance="light" compact capture={step.screen === "plan" ? { src: "/app/plan-sam-light-818.png", alt: "Plated’s Plan screen showing Sam’s avatar, Pizza Night, and Sam is cooking" } : undefined} /></div>
      </section>)}
    </div>
  </div>;
}
