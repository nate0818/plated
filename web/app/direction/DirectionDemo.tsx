"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import HeroPreview from "../components/HeroPreview";
import { householdCooks } from "../components/household";
import usePreviewMotion from "../components/usePreviewMotion";
import styles from "./direction.module.css";

export default function DirectionDemo() {
  const stage = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  const [selection, setSelection] = useState(0);
  const { active, running, ready, toggle, select } = usePreviewMotion(stage, 3, 6500, loaded);
  return <div ref={stage} id="shared-plan" className={styles.demo} aria-label="A week in the sample household’s meal plan">
    <div className={styles.demoPlan}>
      <div className={styles.demoHeading} data-reveal><span className={styles.demoLabel}>Your household’s week</span><div className={styles.tinyPeople} aria-hidden="true"><span><svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="12" cy="8" r="3.5" /><path d="M5 21v-2a7 7 0 0 1 14 0v2" /></svg></span><span>S</span><span>R</span></div></div>
      <h2 data-reveal>You’ve got tonight<br />Sam’s got tomorrow</h2>
      <ul className={styles.dinners} aria-label="Example cooking nights" data-reveal="stagger">
        {householdCooks.map((cook,index)=><li key={cook.name}><button type="button" className={styles.dinner} data-active={active===index} data-running={running} aria-pressed={active===index} aria-controls="direction-plan-screen" onClick={()=>{ select(index); setSelection(value=>value+1); }}>
          <span className={styles.dishPhoto}><Image src={`/editorial/${cook.image}.webp`} alt="" width={160} height={160} sizes="(max-width: 480px) 58px, 72px" /><span className={styles.cookBadge} data-tone={cook.tone} aria-hidden="true">{cook.initial ?? <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="12" cy="8" r="3.5" /><path d="M5 21v-2a7 7 0 0 1 14 0v2" /></svg>}</span></span>
          <span className={styles.dinnerDetails}><span>{cook.night}</span><strong>{index===0?"Salmon Night":index===1?"Pizza Night":"Steak Bowls"}</strong><span className={styles.dinnerCook}>{cook.name==="You"?"You’re cooking":`${cook.name} is cooking`}</span></span>
          <span className={styles.activeMark} aria-hidden="true"><svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M3 10h13m-5-5 5 5-5 5" /></svg></span>
          {active === index && <span key={`${active}-${selection}`} className={styles.dinnerProgress} aria-hidden="true" />}
        </button></li>)}
      </ul>
      <p className={styles.demoNote}>Pick a night to see who’s cooking.</p>
    </div>
    <div className={styles.demoDevice} id="direction-plan-screen">
      <div data-reveal><HeroPreview active={active} running={running} ready={ready} onToggle={toggle} onReady={()=>setLoaded(true)} /></div>
    </div>
    <div className={styles.demoFootnote}><span>Real app screens · Example household</span></div>
  </div>;
}
