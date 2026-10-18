import Image from "next/image";
import { householdCooks } from "./household";
import styles from "./HouseholdCooks.module.css";

export default function HouseholdCooks({ active, running = false, compact = false }: { active?: number; running?: boolean; compact?: boolean }) {
  return <ul className={styles.cooks} data-running={running} data-compact={compact} aria-label="Example household cooking nights">
    {householdCooks.map((cook, index) => <li key={cook.name} className={styles.cook} data-active={active === index}>
      <span className={styles.avatarPosition}>
        <span className={styles.avatar} data-tone={cook.tone} aria-hidden="true">
          {cook.initial ?? <svg viewBox="0 0 32 32" width="32" height="32" fill="none" stroke="currentColor" strokeWidth="1.6"><circle cx="16" cy="11" r="5" /><path d="M6.5 27v-2a9.5 9.5 0 0 1 19 0v2" /></svg>}
          <span className={styles.mealBadge}><Image src={`/editorial/${cook.image}.webp`} alt="" width={80} height={80} sizes="34px" /></span>
        </span>
      </span>
      <span className={styles.name}>{cook.name}</span>
      <span className={styles.meal}>{cook.meal}<span>{cook.night}</span></span>
    </li>)}
  </ul>;
}
