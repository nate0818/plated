"use client";

import { useEffect } from "react";

// A plate in the tab, and every couple of seconds a new dish lands on it.
//
// Browsers will not play an animated SVG or GIF as a favicon (Firefox is
// the lone exception), so the only way to animate one everywhere is to
// redraw it on a canvas and swap the <link rel="icon"> href. The static
// dot from icon.tsx stays as the fallback: bookmarks, history and no-JS
// all get that.
const DISHES = ["🌮", "🍕", "🍔", "🥞", "🍗", "🥪", "🌯", "🍤", "🥐", "🧇"];
const SIZE = 64;
const HOLD_MS = 1800;   // how long a dish sits on the plate
const DROP_FRAMES = 6;  // frames of the landing spring
const FRAME_MS = 40;

function drawPlate(ctx: CanvasRenderingContext2D) {
  ctx.clearRect(0, 0, SIZE, SIZE);
  ctx.fillStyle = "#FFFFFF";
  ctx.fillRect(0, 0, SIZE, SIZE);
  const c = SIZE / 2;
  ctx.beginPath();
  ctx.arc(c, c, 29, 0, Math.PI * 2);
  ctx.fillStyle = "#FFFFFF";
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = "#E4DDD3"; // hairline, darkened a step: at 16px the real one vanishes
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(c, c, 22, 0, Math.PI * 2);
  ctx.lineWidth = 1.5;
  ctx.strokeStyle = "#F0EBE4";
  ctx.stroke();
}

function drawDish(ctx: CanvasRenderingContext2D, glyph: string, scale: number, lift: number) {
  const c = SIZE / 2;
  ctx.save();
  ctx.translate(c, c - lift);
  ctx.scale(scale, scale);
  ctx.font = `34px "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(glyph, 0, 2);
  ctx.restore();
}

export default function AnimatedFavicon() {
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const link =
      document.querySelector<HTMLLinkElement>('link[rel="icon"]') ??
      Object.assign(document.createElement("link"), { rel: "icon" });
    if (!link.parentNode) document.head.appendChild(link);
    const original = { href: link.href, type: link.type, sizes: link.getAttribute("sizes") };

    const canvas = document.createElement("canvas");
    canvas.width = SIZE;
    canvas.height = SIZE;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let dish = Math.floor(Math.random() * DISHES.length);
    let frame = 0;
    let timer = 0;

    const paint = () => {
      drawPlate(ctx);
      // The landing: overshoots a touch on the way in, the way plPop does.
      const t = Math.min(frame, DROP_FRAMES) / DROP_FRAMES;
      const ease = 1 - Math.pow(1 - t, 3);
      const overshoot = t < 1 ? 1 + 0.18 * Math.sin(t * Math.PI) : 1;
      drawDish(ctx, DISHES[dish], ease * overshoot, (1 - ease) * 18);
      link.type = "image/png";
      link.removeAttribute("sizes");
      link.href = canvas.toDataURL("image/png");
    };

    const tick = () => {
      paint();
      if (frame < DROP_FRAMES) {
        frame += 1;
        timer = window.setTimeout(tick, FRAME_MS);
      } else {
        frame = 0;
        dish = (dish + 1) % DISHES.length;
        timer = window.setTimeout(tick, HOLD_MS);
      }
    };

    // A hidden tab keeps its last frame; the loop resumes when it is looked at.
    const onVisibility = () => {
      window.clearTimeout(timer);
      if (!document.hidden) tick();
    };
    document.addEventListener("visibilitychange", onVisibility);
    tick();

    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisibility);
      link.href = original.href;
      if (original.type) link.type = original.type;
      if (original.sizes) link.setAttribute("sizes", original.sizes);
    };
  }, []);

  return null;
}
