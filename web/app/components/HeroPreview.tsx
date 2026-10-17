"use client";

import { useEffect, useRef, useState, type RefObject } from "react";
import Image from "next/image";
import { getImageProps } from "next/image";
import styles from "./HeroPreview.module.css";

const screenSizes = "(max-width: 760px) 280px, 326px";
const poster = getImageProps({ src: "/app/plan-light-818.png", alt: "", width: 326, height: 709 }).props.src;

export type HeroPhase = "app" | "sam";

type HeroPreviewProps = {
  hero: RefObject<HTMLElement | null>;
  onPhaseChange: (phase: HeroPhase) => void;
  onMotionChange: (running: boolean) => void;
};

export default function HeroPreview({ hero, onPhaseChange, onMotionChange }: HeroPreviewProps) {
  const video = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const [phase, setPhase] = useState<HeroPhase>("app");
  const [loaded, setLoaded] = useState(false);
  const intent = useRef<"auto" | "play" | "pause">("auto");
  const updatePlayback = useRef<() => void>(() => {});

  useEffect(() => {
    const player = video.current;
    const section = hero.current;
    if (!player || !section) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const connection = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
    let heroVisible = false;
    let phoneVisible = false;
    let currentPhase: HeroPhase = "app";
    let remaining = 5000;
    let holdStarted = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let disposed = false;

    function stopHold() {
      if (timer === undefined) return;
      clearTimeout(timer);
      timer = undefined;
      remaining = Math.max(0, remaining - (performance.now() - holdStarted));
    }

    function update() {
      if (!player || disposed) return;
      const running = heroVisible && !document.hidden && intent.current !== "pause" &&
        (intent.current === "play" || (!motion.matches && !connection?.saveData));
      setPlaying(running);
      onMotionChange(running);
      if (!running || !phoneVisible) {
        player.pause();
        stopHold();
        return;
      }
      if (currentPhase === "sam") {
        player.pause();
        if (timer === undefined) {
          holdStarted = performance.now();
          timer = setTimeout(() => {
            timer = undefined;
            remaining = 5000;
            currentPhase = "app";
            setPhase("app");
            onPhaseChange("app");
            player.currentTime = 0;
            update();
          }, remaining);
        }
        return;
      }
      if (!player.getAttribute("src")) {
        player.src = "/app/plated-collaboration-818.mp4";
        setLoaded(true);
      }
      if (player.paused) void player.play().catch(() => {
        // Scrolling away can interrupt play(); leave that pause resumable.
        if (!disposed && heroVisible && phoneVisible && !document.hidden) {
          intent.current = "pause";
          update();
        }
      });
    }

    function showNextCook() {
      currentPhase = "sam";
      remaining = 5000;
      setPhase("sam");
      onPhaseChange("sam");
      update();
    }

    function showPlaybackError() {
      intent.current = "pause";
      update();
    }

    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (entry.target === section) heroVisible = entry.isIntersecting;
        if (entry.target === player) phoneVisible = entry.isIntersecting && entry.intersectionRatio >= .15;
      }
      update();
    }, { threshold: [0, .15] });
    updatePlayback.current = update;
    observer.observe(section);
    observer.observe(player);
    player.addEventListener("ended", showNextCook);
    player.addEventListener("error", showPlaybackError);
    motion.addEventListener("change", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      disposed = true;
      updatePlayback.current = () => {};
      stopHold();
      observer.disconnect();
      player.removeEventListener("ended", showNextCook);
      player.removeEventListener("error", showPlaybackError);
      motion.removeEventListener("change", update);
      document.removeEventListener("visibilitychange", update);
      player.pause();
    };
  }, [hero, onPhaseChange, onMotionChange]);

  return <figure className={styles.preview} data-phase={phase}>
    <div className={styles.phone}>
      <div className={styles.screen}>
      <video ref={video} poster={poster} width="1206" height="2622" muted playsInline preload="none" aria-label="Plated app recording, starting on Plan and opening the recipe book" aria-hidden={phase !== "app"}>
        Your browser cannot play this preview. Plated brings your meal plan and recipes together.
      </video>
      {loaded && <Image className={styles.capture} src="/app/plan-sam-light-818.png" width={326} height={709} sizes={screenSizes} loading="eager" alt="Plated’s Plan screen showing Sam’s avatar, Pizza Night, and Sam is cooking tomorrow" aria-hidden={phase !== "sam"} />}
      </div>
    </div>
    <figcaption className={styles.caption}>
      <span>Inside Plated</span>
      <button onClick={() => {
        intent.current = playing ? "pause" : "play";
        if (!playing && video.current?.error) video.current.load();
        updatePlayback.current();
      }} aria-label={playing ? "Pause collaboration preview" : "Play collaboration preview"}>
        <svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{playing ? <path d="M7 4v12m6-12v12" /> : <path d="m7 4 8 6-8 6Z" />}</svg>
        {playing ? "Pause" : "Play"}
      </button>
    </figcaption>
  </figure>;
}
