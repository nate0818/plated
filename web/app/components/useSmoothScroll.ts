"use client";

import { useEffect } from "react";

/** Ease wheel input on desktop; keep touch, keyboard and nested scrolling native. */
export default function useSmoothScroll(pathname: string) {
  useEffect(() => {
    const finePointer = window.matchMedia("(pointer: fine)");
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    let revision = 0;
    let dispose = () => {};

    async function configure() {
      const request = ++revision;
      dispose();
      dispose = () => {};
      if (!finePointer.matches || reduced.matches) return;

      // Touch devices never need to download the scroll engine.
      const scrollModule = await import("lenis").catch(() => null);
      if (!scrollModule || request !== revision) return;
      const scroller = new scrollModule.default({
        lerp: .09,
        smoothWheel: true,
        syncTouch: false,
        allowNestedScroll: true,
        stopInertiaOnNavigate: true,
        prevent: node => node.matches("dialog, textarea, select, [data-native-scroll]"),
      });
      let frame = 0;
      let historyFrame = 0;
      let previousTime = 0;
      let animationTime = 0;

      // Advance only while moving. A local clock prevents an idle gap from
      // completing the next gesture in one frame; no continuous idle RAF loop.
      function tick(time: number) {
        frame = 0;
        animationTime += previousTime ? Math.min(time - previousTime, 64) : 1000 / 60;
        previousTime = time;
        scroller.raf(animationTime);
        if (scroller.isScrolling === "smooth") wake();
        else previousTime = 0;
      }
      function wake() {
        if (!frame && !document.hidden) frame = window.requestAnimationFrame(tick);
      }
      function cancelInertia() {
        if (!scroller.isStopped) scroller.scrollTo(scroller.actualScroll, { immediate: true });
      }
      function syncLock() {
        if (document.hidden || document.querySelector("dialog[open]")) {
          scroller.stop();
          window.cancelAnimationFrame(frame);
          frame = previousTime = 0;
        } else scroller.start();
      }
      function onKeyDown(event: KeyboardEvent) {
        if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "].includes(event.key)) cancelInertia();
      }
      function onHistory() {
        cancelInertia();
        window.cancelAnimationFrame(historyFrame);
        // Next.js manages scroll restoration. Restore same-page hashes after
        // its history handler, without replaying a long animation on Back.
        historyFrame = window.requestAnimationFrame(() => {
          historyFrame = 0;
          if (location.pathname !== pathname) return;
          let target: HTMLElement | null = null;
          try { target = document.getElementById(decodeURIComponent(location.hash.slice(1))); }
          catch { return; }
          if (location.hash && !target) return;
          // History may have moved the native viewport since popstate fired.
          // Reconcile it before calculating the anchor's document position.
          scroller.resize();
          scroller.scrollTo(target ?? 0, { immediate: true });
        });
      }
      function onAnchor(event: MouseEvent) {
        if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        const link = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>("a[href]") : null;
        if (!link || link.hasAttribute("download") || (link.target && link.target !== "_self")) return;
        const url = new URL(link.href);
        if (url.origin !== location.origin || url.pathname !== location.pathname || url.search !== location.search || !url.hash) return;
        let target: HTMLElement | null;
        try { target = document.getElementById(decodeURIComponent(url.hash.slice(1))); }
        catch { return; }
        if (!target || scroller.isStopped) return;

        // Own same-page anchors before Next.js or the browser starts a second
        // scroll. Lenis reads each target's existing CSS scroll-margin.
        event.preventDefault();
        if (location.hash !== url.hash) history.pushState(null, "", url);
        scroller.resize();
        scroller.scrollTo(target, {
          duration: .9,
          lerp: 0,
          easing: value => 1 - Math.pow(1 - value, 4),
          onStart: wake,
          onComplete: () => {
            if (!target.hasAttribute("tabindex")) {
              target.setAttribute("tabindex", "-1");
              target.addEventListener("blur", () => target.removeAttribute("tabindex"), { once: true });
            }
            target.focus({ preventScroll: true });
          },
        });
      }

      const modalObserver = new MutationObserver(syncLock);
      modalObserver.observe(document.body, { subtree: true, attributes: true, attributeFilter: ["open"] });
      const unsubscribe = scroller.on("virtual-scroll", wake);
      document.addEventListener("click", onAnchor, true);
      document.addEventListener("keydown", onKeyDown, true);
      document.addEventListener("pointerdown", cancelInertia, { passive: true });
      document.addEventListener("visibilitychange", syncLock);
      window.addEventListener("popstate", onHistory);
      syncLock();
      dispose = () => {
        window.cancelAnimationFrame(frame);
        window.cancelAnimationFrame(historyFrame);
        modalObserver.disconnect();
        unsubscribe();
        document.removeEventListener("click", onAnchor, true);
        document.removeEventListener("keydown", onKeyDown, true);
        document.removeEventListener("pointerdown", cancelInertia);
        document.removeEventListener("visibilitychange", syncLock);
        window.removeEventListener("popstate", onHistory);
        scroller.destroy();
      };
    }

    void configure();
    finePointer.addEventListener("change", configure);
    reduced.addEventListener("change", configure);
    return () => {
      revision++;
      dispose();
      finePointer.removeEventListener("change", configure);
      reduced.removeEventListener("change", configure);
    };
  }, [pathname]);
}
