"use client";

import { useEffect, useRef, useState } from "react";
import { getImageProps } from "next/image";
import styles from "./HeroPreview.module.css";

const poster = getImageProps({ src: "/app/plan-light-818.png", alt: "", width: 326, height: 709 }).props.src;

export default function HeroPreview() {
  const video = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const intent = useRef<"auto" | "play" | "pause">("auto");

  useEffect(() => {
    const player = video.current;
    if (!player) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const connection = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
    let visible = false;
    function update() {
      if (!player) return;
      if (visible && !document.hidden && intent.current !== "pause" &&
          (intent.current === "play" || (!motion.matches && !connection?.saveData))) {
        if (!player.getAttribute("src")) player.src = "/app/plated-preview-818.mp4";
        void player.play().catch(() => { /* The Play button remains available if autoplay is blocked. */ });
      } else player.pause();
    }
    const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting && entry.intersectionRatio >= 0.25; update(); }, { threshold: 0.25 });
    observer.observe(player);
    motion.addEventListener("change", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      observer.disconnect();
      motion.removeEventListener("change", update);
      document.removeEventListener("visibilitychange", update);
      player.pause();
    };
  }, []);

  return <figure className={styles.preview}>
    <div className={styles.phone}>
      <video ref={video} poster={poster} width="1206" height="2622" muted loop playsInline preload="none" aria-label="Plated app recording, starting on Plan and opening the recipe book" onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)}>
        Your browser cannot play this preview. Plated brings your meal plan and recipes together.
      </video>
    </div>
    <figcaption className={styles.caption}>
      <span>Inside Plated</span>
      <button onClick={() => {
        intent.current = playing ? "pause" : "play";
        if (playing) video.current?.pause();
        else if (video.current) {
          if (!video.current.getAttribute("src")) video.current.src = "/app/plated-preview-818.mp4";
          void video.current.play().catch(() => { /* Keep the poster and a retryable Play control. */ });
        }
      }} aria-label={playing ? "Pause app preview" : "Play app preview"}>
        <svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{playing ? <path d="M7 4v12m6-12v12" /> : <path d="m7 4 8 6-8 6Z" />}</svg>
        {playing ? "Pause" : "Play"}
      </button>
    </figcaption>
  </figure>;
}
