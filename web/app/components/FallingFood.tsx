import styles from "./FallingFood.module.css";

// Dinner, not a fruit bowl: the set is what a household actually cooks
// with, and the people and tools doing the cooking.
const FOOD = [
  "🍅", "🧑‍🍳", "🥑", "🍋", "🔪", "🧄", "🧅", "👩‍🍳", "🥕", "🌽",
  "🍄", "🥦", "🫑", "🧂", "🍝", "🍕", "👨‍🍳", "🥘", "🍲", "🥗",
  "🍳", "🥖", "🍽️", "🧀", "🍤", "🍗", "🥄", "🌮", "🥟", "🍜",
  "🫕", "🫒", "🌶️", "🥬", "🍴", "🥣", "🔥",
];

// Seeded so the server and the client draw the same sky. Math.random here
// would hydrate to a different layout than it rendered, and React would
// flash every emoji to a new spot on load.
function mulberry32(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type Piece = {
  glyph: string;
  left: number;      // % of width
  size: number;      // px
  duration: number;  // s, one full fall
  delay: number;     // s, negative so the sky is already full on load
  sway: number;      // px of side-to-side drift
  spin: number;      // deg over one fall, signed
};

function makePieces(count: number, seed: number): Piece[] {
  const rand = mulberry32(seed);
  return Array.from({ length: count }, (_, i) => ({
    // Cycle through the set so no glyph repeats before every other has fallen.
    glyph: FOOD[(i * 11) % FOOD.length],
    left: rand() * 100,
    size: 22 + rand() * 18,
    duration: 22 + rand() * 18,
    delay: -rand() * 40,
    sway: 16 + rand() * 30,
    spin: (rand() < 0.5 ? -1 : 1) * (40 + rand() * 80),
  }));
}

// A background, so it is decoration to a screen reader and to the pointer:
// aria-hidden and pointer-events none, and it disappears under Reduce Motion
// rather than freezing mid-air, which would read as broken.
export default function FallingFood({ count = 22 }: { count?: number }) {
  const pieces = makePieces(count, 8_18);
  return (
    <div className={styles.sky} aria-hidden="true">
      {pieces.map((p, i) => (
        <span
          key={i}
          className={styles.piece}
          style={
            {
              left: `${p.left}%`,
              fontSize: `${p.size}px`,
              "--fall": `${p.duration}s`,
              "--delay": `${p.delay}s`,
              "--sway": `${p.sway}px`,
              "--spin": `${p.spin}deg`,
            } as React.CSSProperties
          }
        >
          {p.glyph}
        </span>
      ))}
    </div>
  );
}
