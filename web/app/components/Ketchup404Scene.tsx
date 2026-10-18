"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { SiteArrow } from "./SiteFrame";
import styles from "./Ketchup404Scene.module.css";

export default function Ketchup404Scene() {
  const router = useRouter();
  return (
    <div className={styles.experience}>
      <div className={styles.copy} data-reveal="stagger">
        <p className={styles.eyebrow}>404 · Page not found</p>
        <h1 className={styles.title}>That page<br />isn’t here</h1>
        <p className={styles.lede}>The link may have changed. Head back to Plated, or return to the previous page.</p>
        <div className={styles.actions}>
          <Link href="/" className={styles.primary}>Back to Plated <SiteArrow /></Link>
          <button
            type="button"
            className={styles.secondary}
            onClick={() => window.history.length > 1 ? router.back() : router.push("/")}
          >
            <span aria-hidden="true">←</span> Go back
          </button>
        </div>
      </div>
      <div className={styles.plate} aria-hidden="true" data-reveal>
        <svg viewBox="0 0 480 400" fill="none">
          <path d="M90 132v83h58m-13-83v138m210-138v83h58m-13-83v138" stroke="currentColor" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="246" cy="201" r="71" fill="#F7F6F0" stroke="#B9C6AD" strokeWidth="2" />
          <circle cx="246" cy="201" r="56" stroke="#DDE1D5" strokeWidth="1.5" />
          <path d="M230 201h32" stroke="#C6D0BD" strokeWidth="2" strokeLinecap="round" />
          <path d="M65 79v28m-7-28v15m14-15v15m-7 13v36m361 112v55m-7-56c0-21 14-21 14 0v10h-14v-10Z" stroke="#9BAA8F" strokeWidth="2.5" strokeLinecap="round" />
        </svg>
        <span>Let’s find your way back</span>
      </div>
    </div>
  );
}
