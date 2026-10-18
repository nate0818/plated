"use client";

import { useRef, useState, type ReactNode } from "react";
import HeroPreview from "./HeroPreview";
import HouseholdCooks from "./HouseholdCooks";
import { householdCooks } from "./household";
import usePreviewMotion from "./usePreviewMotion";
import pageStyles from "../page.module.css";
import styles from "./HeroCollaboration.module.css";

export default function HeroCollaboration({ intro, actions }: { intro: ReactNode; actions: ReactNode }) {
  const phone = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  const { active, running, ready, toggle } = usePreviewMotion(phone, householdCooks.length, 6000, loaded);

  return <section className={pageStyles.hero} aria-labelledby="hero-title">
    <div className={pageStyles.heroCopy}>
      {intro}
      <div className={styles.household}>
        <HouseholdCooks active={active} running={running} />
        <div className={styles.cooking}>
          <span aria-hidden="true" />
          <div className={styles.status}>
            {householdCooks.map((cook, index) => <p key={cook.name} data-active={active === index} aria-hidden={active !== index}>{cook.description}</p>)}
          </div>
        </div>
      </div>
      {actions}
    </div>
    <div ref={phone} className={pageStyles.heroProduct}>
      <HeroPreview active={active} running={running} ready={ready} onToggle={toggle} onReady={() => setLoaded(true)} />
    </div>
  </section>;
}
