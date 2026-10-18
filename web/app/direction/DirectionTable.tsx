"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import usePreviewMotion from "../components/usePreviewMotion";
import styles from "./direction.module.css";

const activity = [
  { initial: "S", name: "Sam", action: "shared a recipe", detail: "Tomato & basil rigatoni", tone: "basil" },
  { initial: "R", name: "Riley", action: "left a comment", detail: "“Making this tomorrow”", tone: "mango" },
  { initial: "S", name: "Sam", action: "liked Riley’s comment", detail: "“Making this tomorrow”", tone: "basil" },
  { initial: "S", name: "Sam", action: "replied to Riley", detail: "“Even better with extra Parmesan”", tone: "basil" },
] as const;

function Bookmark({ filled = false }: { filled?: boolean }) {
  return <svg viewBox="0 0 24 24" width="19" height="19" fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M6 3h12v18l-6-4-6 4Z" /></svg>;
}

export default function DirectionTable() {
  const stage = useRef<HTMLElement>(null);
  const [loaded, setLoaded] = useState(false);
  const [saved, setSaved] = useState(false);
  const { active, running, ready, toggle } = usePreviewMotion(stage, 4, 3600, loaded);
  // Show the complete conversation when automatic motion is disabled.
  const phase = ready ? active : 3;
  const event = activity[phase];

  return <figure ref={stage} className={styles.tableStory} data-depth-item data-depth-travel="64" aria-label="An example conversation at your Table">
    <div className={styles.tableComposition} data-reveal>
    <article className={styles.tablePost}>
      <div className={styles.postAuthor}><span className={styles.socialAvatar} data-tone="basil" aria-hidden="true">S</span><div><strong>Sam</strong><span>At your Table · Just now</span></div><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5" aria-label="Invite-only"><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg></div>
      <div className={styles.postPhoto}><Image src="/editorial/table-pasta-candid.webp" alt="A casual kitchen-table photo of Sam’s tomato and basil rigatoni" width={1024} height={1024} sizes="(max-width: 760px) calc(100vw - 64px), 480px" onLoad={() => setLoaded(true)} /></div>
      <div className={styles.postCopy}><h3>Tuesday night pasta</h3><p>This one’s going into the regular rotation.</p><span className={styles.recipeAttachment}><Bookmark />Tomato & basil rigatoni <span>25 min</span></span></div>
      <div className={styles.postActions}>
        <span><svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M4 4h16v12H9l-5 4Z" /></svg>{phase >= 3 ? "2 comments" : phase >= 1 ? "1 comment" : "Comments"}</span>
        <button type="button" aria-pressed={saved} onClick={() => setSaved(value => !value)}><Bookmark filled={saved} />{saved ? "Recipe saved" : "Save recipe"}</button>
      </div>
      <div className={styles.postConversation}>
        <div className={styles.postComment} data-visible={phase >= 1} aria-hidden={phase < 1}><span className={styles.socialAvatar} data-tone="mango" aria-hidden="true">R</span><div><strong>Riley</strong><p>Making this tomorrow</p></div><svg className={styles.commentHeart} data-liked={phase >= 2} viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" strokeWidth="1.5" aria-label={phase >= 2 ? "Liked" : undefined} aria-hidden={phase < 2}><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z" /></svg></div>
        <div className={`${styles.postComment} ${styles.postReply}`} data-visible={phase >= 3} aria-hidden={phase < 3}><span className={styles.socialAvatar} data-tone="basil" aria-hidden="true">S</span><div><strong>Sam</strong><p>Even better with extra Parmesan</p></div></div>
      </div>
    </article>
      <div className={styles.tableActivity}>
        <div key={phase} className={styles.activityContent}>
          <span className={styles.activityAvatar} aria-hidden="true">
            <span className={styles.socialAvatar} data-tone={event.tone}>{event.initial}</span>
            <span className={styles.activityBadge}><svg viewBox="0 0 20 20" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{phase === 0 ? <path d="M5 3h10v14l-5-3-5 3V3Z" /> : phase === 2 ? <path d="M16.8 4.5a4 4 0 0 0-5.7 0L10 5.6 8.9 4.5a4 4 0 0 0-5.7 5.7L10 17l6.8-6.8a4 4 0 0 0 0-5.7Z" /> : <path d="M3 3h14v10H8l-5 4V3Z" />}</svg></span>
          </span>
          <div><p><strong>{event.name}</strong> {event.action}</p><span>{event.detail}</span></div>
          <span className={styles.activityTime}>now</span>
        </div>
      </div>
    </div>
    <figcaption className={styles.tableCaption}><span>Sample post and conversation</span><button type="button" onClick={toggle} aria-label={running ? "Pause Table activity" : "Play Table activity"}><svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">{running ? <path d="M7 4v12m6-12v12" /> : <path d="m7 4 8 6-8 6Z" />}</svg>{running ? "Pause" : "Play"}</button></figcaption>
  </figure>;
}
