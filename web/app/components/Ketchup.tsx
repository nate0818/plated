import styles from "./Ketchup.module.css";

// "404" squeezed out of a bottle, already on the plate: no drawing-on.
// Three layers per stroke: a darker bead underneath for weight, the tomato
// body, and a thin gloss on top so it reads as wet. A turbulence filter
// wobbles every edge so no line is straight, which is the difference
// between ketchup and a red font.
const STROKES = [
  { id: "k1", d: "M27 8 L9 37 C9 38 10 38.5 11 38.5 L38 38" },
  { id: "k2", d: "M31 7 C31.5 20 31 38 31.5 55" },
  { id: "k3", d: "M64 7 C49 7 44.5 19 45 31 C45.5 43 50 55.5 64 55 C78 54.5 82.5 43 82 30 C81.5 18 77 7.5 64 7 Z" },
  { id: "k4", d: "M112 8 L94 37 C94 38 95 38.5 96 38.5 L123 38" },
  { id: "k5", d: "M116 7 C116.5 20 116 38 116.5 55" },
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
          <path key={s.id} id={s.id} d={s.d} />
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
            <use key={s.id} href={`#${s.id}`} />
          ))}
        </g>
        {/* Body. */}
        <g stroke="var(--tomato)" strokeWidth="14">
          {STROKES.map((s) => (
            <use key={s.id} href={`#${s.id}`} />
          ))}
        </g>
        {/* Gloss: a thin pale line riding the top-left of each stroke. */}
        <g stroke="var(--canvas)" strokeWidth="2.6" opacity="0.38" transform="translate(-2.4 -2.8)" strokeDasharray="0.22 0.18">
          {STROKES.map((s) => (
            <use key={s.id} href={`#${s.id}`} />
          ))}
        </g>
        {/* The drip off the last stroke. */}
        <path d="M116.5 55 C116.5 59 116.5 62 116.5 64" stroke="var(--tomato)" strokeWidth="9" />
        <circle cx="116.5" cy="66.5" r="5.2" fill="var(--tomato)" />
        <circle cx="115" cy="65" r="1.6" fill="var(--canvas)" opacity="0.55" />
      </g>
    </svg>
  );
}
