"use client";

import { useEffect, useRef, useState, type RefObject } from "react";

/** One resumable timer per visible preview; never intercepts scrolling. */
export default function usePreviewMotion(target: RefObject<HTMLElement | null>, count: number, duration = 6000, enabled = true) {
  const [active, setActive] = useState(0);
  const [running, setRunning] = useState(false);
  const [ready, setReady] = useState(false);
  const intent = useRef<"auto" | "play" | "pause">("auto");
  const update = useRef<() => void>(() => {});

  useEffect(() => {
    const element = target.current;
    if (!element) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const connection = (navigator as Navigator & { connection?: EventTarget & { saveData?: boolean } }).connection;
    let visible = false;
    let remaining = duration;
    let started = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    function stop() {
      if (timer === undefined) return;
      clearTimeout(timer);
      timer = undefined;
      remaining = Math.max(0, remaining - (performance.now() - started));
    }
    function sync() {
      const permitted = !document.hidden && intent.current !== "pause" &&
        (intent.current === "play" || (!motion.matches && !connection?.saveData));
      if (visible && permitted) setReady(true);
      const playing = visible && enabled && permitted;
      setRunning(playing);
      if (!playing) { stop(); return; }
      if (timer === undefined) {
        started = performance.now();
        timer = setTimeout(() => {
          timer = undefined;
          remaining = duration;
          setActive(value => (value + 1) % count);
          sync();
        }, remaining);
      }
    }
    update.current = sync;
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting && entry.intersectionRatio >= .15;
      sync();
    }, { threshold: [0, .15] });
    observer.observe(element);
    motion.addEventListener("change", sync);
    connection?.addEventListener("change", sync);
    document.addEventListener("visibilitychange", sync);
    return () => {
      update.current = () => {};
      stop();
      observer.disconnect();
      motion.removeEventListener("change", sync);
      connection?.removeEventListener("change", sync);
      document.removeEventListener("visibilitychange", sync);
    };
  }, [target, count, duration, enabled]);

  function toggle() {
    intent.current = running ? "pause" : "play";
    update.current();
  }
  return { active, running, ready, toggle };
}
