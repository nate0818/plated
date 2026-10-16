"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import styles from "./FoodGallery.module.css";

const rows = [
  [
    { file: "salmon", title: "Lemon Butter Salmon", time: "25 min", alt: "Lemon butter salmon with rice and vegetables" },
    { file: "pizza", title: "Pizza Night", time: "37 min", alt: "Homemade pizza with mozzarella and basil" },
    { file: "poke", title: "Poke Night", time: "15 min", alt: "A colourful poke bowl" },
    { file: "pancakes", title: "Pancake Dinner", time: "25 min", alt: "Pancakes with maple syrup" },
  ],
  [
    { file: "skewers", title: "BBQ Skewers", time: "35 min", alt: "Grilled skewers from Plated’s sample cookbook" },
    { file: "rainbow", title: "Rainbow Bowls", time: "20 min", alt: "A bowl of vegetables and grains" },
    { file: "steak", title: "Steak Bowls", time: "27 min", alt: "A steak bowl with rice and vegetables" },
  ],
];

export default function FoodGallery() {
  const section = useRef<HTMLElement>(null);
  const [paused, setPaused] = useState(false);
  const [inView, setInView] = useState(false);
  const [pageVisible, setPageVisible] = useState(true);

  useEffect(() => {
    const node = section.current;
    if (!node) return;
    const observer = new IntersectionObserver(([entry]) => setInView(entry.isIntersecting), { rootMargin: "100px 0px" });
    observer.observe(node);
    const updateVisibility = () => setPageVisible(!document.hidden);
    updateVisibility();
    document.addEventListener("visibilitychange", updateVisibility);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", updateVisibility);
    };
  }, []);

  return <section ref={section} id="recipes" className={styles.section} aria-labelledby="food-title" data-running={inView && pageVisible && !paused}>
    <div className={styles.heading}>
      <h2 id="food-title">Make room for your favourites.</h2>
      <div className={styles.context}>
        <p>Start with Plated&rsquo;s sample cookbook.<br />Make it yours with the recipes you love.</p>
        <button className={styles.motionControl} onClick={() => setPaused(value => !value)} aria-pressed={paused} aria-label={paused ? "Play recipe animation" : "Pause recipe animation"}>
          <svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{paused ? <path d="m7 4 8 6-8 6Z" /> : <path d="M7 4v12m6-12v12" />}</svg>
          {paused ? "Play" : "Pause"}
        </button>
      </div>
    </div>
    <div className={styles.rows}>
      {rows.map((recipes, rowIndex) => <div key={rowIndex} className={styles.row} tabIndex={0} role="region" aria-label={`Sample recipes, row ${rowIndex + 1} of 2`} onFocus={() => setPaused(true)}>
        <div className={styles.track}>
          {[0, 1].map(groupIndex => <ul key={groupIndex} className={`${styles.group} ${groupIndex === 1 ? styles.duplicateGroup : ""}`} aria-hidden={groupIndex === 1 ? true : undefined}>
            {[...recipes, ...recipes].map((recipe, index) => <li key={`${recipe.file}-${index}`} className={`${styles.card} ${index >= recipes.length ? styles.repeat : ""}`} aria-hidden={index >= recipes.length ? true : undefined}>
              <div className={styles.photo}><Image src={`/editorial/${recipe.file}.webp`} alt={groupIndex === 0 && index < recipes.length ? recipe.alt : ""} fill sizes="(max-width: 760px) 248px, 300px" loading="eager" /></div>
              <div className={styles.meta}><h3>{recipe.title}</h3><span>{recipe.time}</span></div>
            </li>)}
          </ul>)}
        </div>
      </div>)}
    </div>
  </section>;
}
