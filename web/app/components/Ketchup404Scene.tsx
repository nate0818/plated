"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import styles from "./Ketchup404Scene.module.css";

export default function Ketchup404Scene() {
  const router = useRouter();

  // The only way off this page, so it has to actually go somewhere.
  // `history.length > 1` is not the test it looks like: a tab opened
  // straight onto a bad URL already reports 2, so the guard passes and
  // back() lands on a blank page. Instead: ask for back, and if we are
  // still standing here a moment later, nothing happened, so go home.
  function goBack() {
    const here = window.location.href;
    router.back();
    window.setTimeout(() => {
      if (window.location.href === here) router.push("/");
    }, 500);
  }

  return (
    <div className={styles.experience}>
      <Image
        src="/404-ketchup/sauce-v2.webp"
        alt="404 written in ketchup"
        width={1536}
        height={1024}
        className={styles.ketchup}
        unoptimized
        preload
      />
      <div className={styles.copy}>
        <h1 className={styles.title}>This page is out of sauce.</h1>
        <p className={styles.lede}>Let’s get you back to something good.</p>
        <div className={styles.actions}>
          <button type="button" className={styles.action} onClick={goBack}>
            <span aria-hidden="true">←</span> Go back
          </button>
        </div>
      </div>
    </div>
  );
}
