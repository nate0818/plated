import { APP_STORE_URL } from "../lib/store";
import styles from "./AppStoreBadge.module.css";

// Unmodified Apple artwork. Keep the release status explicit while the listing
// returns 404; an unavailable badge must not be an active broken download link.
export default function AppStoreBadge({ height = 50, available = false }: { height?: number; available?: boolean }) {
  const artwork = <>
    {/* eslint-disable-next-line @next/next/no-img-element -- Apple's unmodified SVG badge */}
    <img src="/brand/app-store-badge.svg" alt="" height={height} width={Math.round((height * 250) / 83)} /></>;
  return <div className={styles.store}>
    {!available ? <span className={styles.status}>App Store release coming soon</span> : null}
    {available ? <a className={styles.badge} href={APP_STORE_URL} aria-label="Download on the App Store" style={{ height }}>{artwork}</a> : <span className={styles.badge} role="img" aria-label="App Store release coming soon" style={{ height }}>{artwork}</span>}
  </div>;
}
