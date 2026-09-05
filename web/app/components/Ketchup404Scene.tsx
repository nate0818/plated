"use client";

import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import styles from "./Ketchup404Scene.module.css";

export default function Ketchup404Scene() {
  const router = useRouter();
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
          <Link href="/" className={styles.primary}>Back to the kitchen <span aria-hidden="true">↗</span></Link>
          <button
            type="button"
            className={styles.secondary}
            onClick={() => window.history.length > 1 ? router.back() : router.push("/")}
          >
            <span aria-hidden="true">←</span> Go back
          </button>
        </div>
      </div>
    </div>
  );
}
