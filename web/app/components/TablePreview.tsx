"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import usePreviewMotion from "./usePreviewMotion";
import styles from "./TablePreview.module.css";

export default function TablePreview() {
  const preview = useRef<HTMLElement>(null);
  const [loaded, setLoaded] = useState(false);
  const { active, running, toggle } = usePreviewMotion(preview, 3, 4200, loaded);
  return <figure ref={preview} className={styles.preview} data-phase={active} data-running={running} aria-label="Example of sharing a recipe at your Table">
    <div className={styles.post} data-theme="paper">
      <div className={styles.author}>
        <span className={styles.avatar} aria-hidden="true">S</span>
        <div><strong>Sam</strong><span>Shared at your Table</span></div>
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.4" aria-label="Invite-only"><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>
      </div>
      <div className={styles.photo}><Image src="/editorial/pancakes.webp" width={800} height={900} sizes="(max-width: 760px) calc(100vw - 48px), 440px" alt="Sam’s pancake dinner, topped with berries and maple syrup" onLoad={() => setLoaded(true)} /></div>
      <div className={styles.recipe}>
        <h3>Pancake Dinner</h3>
        <p>Breakfast for dinner. Zero regrets, full syrup.</p>
        <div className={styles.actions} aria-hidden="true">
          <span><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.4"><path d="M4 4h16v12H9l-5 4Z" /></svg>3 comments</span>
          <span className={styles.bookmark} data-saved={active === 2}><svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" strokeWidth="1.4"><path d="M6 3h12v18l-6-4-6 4Z" /></svg>{active === 2 ? "Saved" : "Save recipe"}</span>
        </div>
      </div>
      <div className={styles.conversation}>
        <div className={styles.comment} data-visible={active >= 1} aria-hidden={active < 1}>
          <span className={styles.friend} aria-hidden="true">R</span>
          <p><strong>Riley</strong>Best dinner of the week and it isn’t close</p>
        </div>
        <div className={styles.saved} data-visible={active === 2} aria-hidden={active !== 2}>
          <svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="m4 10 4 4 8-8" /></svg> A new favorite in your recipe book
        </div>
      </div>
    </div>
    <figcaption className={styles.caption}><span>An example from your Table</span><button onClick={toggle} aria-label={running ? "Pause Table preview" : "Play Table preview"}><svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{running ? <path d="M7 4v12m6-12v12" /> : <path d="m7 4 8 6-8 6Z" />}</svg>{running ? "Pause" : "Play"}</button></figcaption>
  </figure>;
}
