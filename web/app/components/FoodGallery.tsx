"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import styles from "./FoodGallery.module.css";

export default function FoodGallery() {
  const collection = useRef<HTMLDivElement>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    const node = collection.current;
    if (!node) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) { setRevealed(true); observer.disconnect(); }
    }, { threshold: 0.25 });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return <section id="recipes" className={styles.section} aria-labelledby="food-title">
    <div ref={collection} className={styles.collection} data-revealed={revealed} aria-label="A personal collection of dinner ideas">
      <figure className={`${styles.recipe} ${styles.pizza}`}>
        <Image src="/editorial/pizza.webp" alt="Pizza with mozzarella and basil" width={560} height={640} sizes="(max-width: 760px) 160px, 220px" />
        <figcaption>Pizza night</figcaption>
      </figure>
      <figure className={`${styles.recipe} ${styles.pancakes}`}>
        <Image src="/editorial/pancakes.webp" alt="Pancakes with maple syrup" width={560} height={640} sizes="(max-width: 760px) 160px, 220px" />
        <figcaption>Pancakes for dinner</figcaption>
      </figure>
      <figure className={`${styles.recipe} ${styles.salmon}`}>
        <Image src="/editorial/salmon.webp" alt="Lemon butter salmon with rice and vegetables" width={560} height={640} sizes="(max-width: 760px) 210px, 280px" />
        <figcaption><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4Z" /></svg>Lemon butter salmon</figcaption>
      </figure>
    </div>
    <div className={styles.copy}>
      <p className={styles.eyebrow}>Your recipe book</p>
      <h2 id="food-title">Your favorites{" "}<br />with room for theirs</h2>
      <p className={styles.description}>Save your own recipes and the ones friends share at your Table. Keep them in one place, ready for dinner.</p>
      <a href="#tour-recipes" className={styles.link}>Make the recipe book yours <span aria-hidden="true">↗</span></a>
    </div>
  </section>;
}
