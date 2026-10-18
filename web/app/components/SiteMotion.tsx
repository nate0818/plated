"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import useSmoothScroll from "./useSmoothScroll";

const ease = "cubic-bezier(.16,1,.3,1)";

/** Progressive enhancement: content and native scrolling work without this layer. */
export default function SiteMotion({ children, className }: { children: ReactNode; className: string }) {
  const root = useRef<HTMLDivElement>(null);
  const pathname = usePathname();
  useSmoothScroll(pathname);

  useEffect(() => {
    const page = root.current;
    if (!page) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const desktop = window.matchMedia("(min-width: 761px) and (pointer: fine)");
    const animations = new Set<Animation>();
    const revealed = new WeakSet<Element>();
    const depthInView = new Set<HTMLElement>();
    const depthStages = [...page.querySelectorAll<HTMLElement>("[data-depth]")];
    const navLinks = [...page.querySelectorAll<HTMLAnchorElement>("[data-section-nav] a")];
    const sections = navLinks.flatMap(link => {
      const url = new URL(link.href);
      const section = url.pathname === pathname && url.hash ? document.getElementById(url.hash.slice(1)) : null;
      return section ? [{ link, section }] : [];
    });
    let frame = 0;
    let revealObserver: IntersectionObserver | undefined;

    function animate(element: Element, index: number) {
      const line = element.getAttribute("data-reveal") === "line";
      const animation = element.animate(
        line
          ? [{ opacity: .15, transform: "translateY(26px)", clipPath: "inset(0 0 100% 0)" }, { opacity: 1, transform: "translateY(0)", clipPath: "inset(0 0 0% 0)" }]
          : [{ opacity: .15, transform: "translateY(22px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: line ? 850 : 720, delay: Math.min(index, 4) * 85, easing: ease, fill: "backwards" },
      );
      animations.add(animation);
      animation.finished.then(() => animations.delete(animation)).catch(() => {});
    }

    function observeReveals() {
      revealObserver?.disconnect();
      if (reduced.matches) {
        animations.forEach(animation => animation.cancel());
        animations.clear();
        return;
      }
      revealObserver = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (!entry.isIntersecting || revealed.has(entry.target)) return;
          revealed.add(entry.target);
          revealObserver?.unobserve(entry.target);
          // Don't animate content the visitor has already passed, or replay on resize.
          if (entry.boundingClientRect.bottom < 0) return;
          const group = entry.target.getAttribute("data-reveal") === "stagger";
          const elements = group ? [...entry.target.children] : [entry.target];
          elements.forEach((element, index) => animate(element, index));
        });
      }, { threshold: 0, rootMargin: "0px 0px -32px 0px" });
      page?.querySelectorAll("[data-reveal]").forEach(element => {
        if (!revealed.has(element) && !element.parentElement?.closest('[data-reveal="stagger"]')) revealObserver?.observe(element);
      });
    }

    function paintScroll() {
      frame = 0;
      const viewport = window.innerHeight;
      const header = page?.querySelector("[data-site-header]");
      const anchorLine = Math.max((header?.getBoundingClientRect().height ?? 76) + 96, viewport * .5);
      const current = sections.filter(({ section }) => section.getBoundingClientRect().top <= anchorLine).at(-1);
      // Read positions together before writing styles; no animation loop while idle.
      const depths = [...depthInView].map(stage => ({
        items: [...stage.querySelectorAll<HTMLElement>("[data-depth-item]")],
        rect: stage.getBoundingClientRect(),
      }));
      const scrolled = String(window.scrollY > 24);
      if (page && page.dataset.scrolled !== scrolled) page.dataset.scrolled = scrolled;
      for (const { link } of sections) {
        if (link === current?.link) {
          if (link.getAttribute("aria-current") !== "location") link.setAttribute("aria-current", "location");
        } else if (link.hasAttribute("aria-current")) link.removeAttribute("aria-current");
      }
      for (const { items, rect } of depths) {
        const progress = desktop.matches && !reduced.matches
          ? Math.max(-.5, Math.min(.5, (rect.top + rect.height / 2 - viewport / 2) / (viewport + rect.height)))
          : 0;
        for (const item of items) {
          const travel = Number(item.dataset.depthTravel ?? 96);
          item.style.setProperty("--depth-offset", `${(progress * travel).toFixed(2)}px`);
        }
      }
    }
    function scheduleScroll() {
      if (!frame && !document.hidden) frame = window.requestAnimationFrame(paintScroll);
    }
    const depthObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) depthInView.add(entry.target as HTMLElement);
        else depthInView.delete(entry.target as HTMLElement);
      });
      scheduleScroll();
    });
    depthStages.forEach(stage => depthObserver.observe(stage));
    // Accordion and image layout changes can move a section without a scroll event.
    const resizeObserver = new ResizeObserver(scheduleScroll);
    const main = page.querySelector("main");
    if (main) resizeObserver.observe(main);
    function updateMotion() { observeReveals(); scheduleScroll(); }

    observeReveals();
    scheduleScroll();
    window.addEventListener("scroll", scheduleScroll, { passive: true });
    window.addEventListener("resize", scheduleScroll, { passive: true });
    document.addEventListener("visibilitychange", scheduleScroll);
    reduced.addEventListener("change", updateMotion);
    desktop.addEventListener("change", scheduleScroll);
    return () => {
      window.cancelAnimationFrame(frame);
      revealObserver?.disconnect();
      depthObserver.disconnect();
      resizeObserver.disconnect();
      animations.forEach(animation => animation.cancel());
      depthStages.forEach(stage => stage.querySelectorAll<HTMLElement>("[data-depth-item]").forEach(item => item.style.removeProperty("--depth-offset")));
      window.removeEventListener("scroll", scheduleScroll);
      window.removeEventListener("resize", scheduleScroll);
      document.removeEventListener("visibilitychange", scheduleScroll);
      reduced.removeEventListener("change", updateMotion);
      desktop.removeEventListener("change", scheduleScroll);
    };
  }, [pathname]);

  return <div ref={root} className={className}>{children}</div>;
}
