"use client";

import { useCallback, useRef, useState, type ReactNode } from "react";
import Image from "next/image";
import HeroPreview, { type HeroPhase } from "./HeroPreview";
import pageStyles from "../page.module.css";
import styles from "./HeroCollaboration.module.css";

const cooks = [
  { name: "You", initial: "N", meal: "Salmon", night: "Tonight", image: "salmon", tone: "oat" },
  { name: "Sam", initial: "S", meal: "Pizza", night: "Tomorrow", image: "pizza", tone: "basil" },
  { name: "Riley", initial: "R", meal: "Steak", night: "Tuesday", image: "steak", tone: "mango" },
] as const;

export default function HeroCollaboration({ intro, actions }: { intro: ReactNode; actions: ReactNode }) {
  const hero = useRef<HTMLElement>(null);
  const [phase, setPhase] = useState<HeroPhase>("app");
  const [running, setRunning] = useState(false);
  const [started, setStarted] = useState(false);
  const updateMotion = useCallback((active: boolean) => {
    setRunning(active);
    if (active) setStarted(true);
  }, []);

  return <section ref={hero} className={pageStyles.hero} aria-labelledby="hero-title">
    <div className={pageStyles.heroCopy}>
      {intro}
      <div className={styles.household} data-phase={phase} data-running={running} data-started={started}>
        <ul className={styles.cooks} aria-label="Example household cooking nights">
          {cooks.map(cook => <li key={cook.name} className={styles.cook}>
            <div className={styles.avatarPosition}>
              <div className={styles.avatarEntry}>
                <span className={styles.avatar} data-tone={cook.tone} aria-hidden="true">
                  {cook.initial}
                  <span className={styles.mealBadge}><Image src={`/editorial/${cook.image}.webp`} alt="" width={80} height={80} sizes="34px" /></span>
                </span>
              </div>
            </div>
            <span className={styles.name}>{cook.name}</span>
            <span className={styles.meal}>{cook.meal}<span>{cook.night}</span></span>
          </li>)}
        </ul>
        <p className={styles.cooking}><span aria-hidden="true" />{phase === "sam" ? "Sam’s cooking tomorrow" : "You’re cooking tonight"}</p>
      </div>
      {actions}
    </div>
    <div className={pageStyles.heroProduct}>
      <HeroPreview hero={hero} onPhaseChange={setPhase} onMotionChange={updateMotion} />
    </div>
  </section>;
}
