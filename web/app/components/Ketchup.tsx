import styles from "./Ketchup.module.css";

// "404" squeezed out of a bottle. Three layers per stroke: a darker bead
// underneath for weight, the tomato body, and a thin gloss on top so it
// reads as wet. A turbulence filter wobbles every edge so no line is
// straight, which is the difference between ketchup and a red font.
const STROKES = [
  { id: "k1", d: "M27 8 L9 37 C9 38 10 38.5 11 38.5 L38 38", delay: 0.1 },
  { id: "k2", d: "M31 7 C31.5 20 31 38 31.5 55", delay: 0.5 },
  { id: "k3", d: "M64 7 C49 7 44.5 19 45 31 C45.5 43 50 55.5 64 55 C78 54.5 82.5 43 82 30 C81.5 18 77 7.5 64 7 Z", delay: 0.85, dur: 0.6 },
  { id: "k4", d: "M112 8 L94 37 C94 38 95 38.5 96 38.5 L123 38", delay: 1.4 },
  { id: "k5", d: "M116 7 C116.5 20 116 38 116.5 55", delay: 1.8 },
];

export default function Ketchup() {
  return (
    <svg
      className={styles.ketchup}
      viewBox="-4 -4 136 76"
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        {STROKES.map((s) => (
          <path key={s.id} id={s.id} d={s.d} pathLength={1} />
        ))}
        <filter id="ketchupEdge" x="-10%" y="-10%" width="120%" height="120%">
          <feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="7" result="noise" />
          <feDisplacementMap in="SourceGraphic" in2="noise" scale="3.2" xChannelSelector="R" yChannelSelector="G" />
        </filter>
        <filter id="ketchupSoft" x="-10%" y="-10%" width="120%" height="130%">
          <feGaussianBlur stdDeviation="0.9" />
        </filter>
      </defs>

      <g filter="url(#ketchupEdge)">
        {/* Bead: the darker edge ketchup gets where it is thickest. */}
        <g stroke="var(--tomato-pressed)" strokeWidth="15.5" transform="translate(0 1.6)" filter="url(#ketchupSoft)">
          {STROKES.map((s) => (
            <use key={s.id} href={`#${s.id}`} className={styles.draw} style={{ animationDelay: `${s.delay}s`, animationDuration: `${s.dur ?? 0.42}s` }} />
          ))}
        </g>
        {/* Body. */}
        <g stroke="var(--tomato)" strokeWidth="14">
          {STROKES.map((s) => (
            <use key={s.id} href={`#${s.id}`} className={styles.draw} style={{ animationDelay: `${s.delay}s`, animationDuration: `${s.dur ?? 0.42}s` }} />
          ))}
        </g>
        {/* Gloss: a thin pale line riding the top-left of each stroke. */}
        <g stroke="var(--canvas)" strokeWidth="3.2" opacity="0.5" transform="translate(-2.6 -3)" strokeDasharray="0.18 0.14">
          {STROKES.map((s) => (
            <use key={s.id} href={`#${s.id}`} className={styles.draw} style={{ animationDelay: `${s.delay + 0.1}s`, animationDuration: `${s.dur ?? 0.42}s` }} />
          ))}
        </g>
        {/* The drip off the last stroke. */}
        <path className={styles.drip} d="M116.5 55 C116.5 59 116.5 62 116.5 64" stroke="var(--tomato)" strokeWidth="9" pathLength={1} />
        <circle className={styles.drop} cx="116.5" cy="66.5" r="5.2" fill="var(--tomato)" />
        <circle className={styles.drop} cx="115" cy="65" r="1.6" fill="var(--canvas)" opacity="0.55" />
      </g>
    </svg>
  );
}
