import { APP_STORE_URL } from "../lib/store";
import styles from "./AppStoreBadge.module.css";

// Apple's own badge, served by Apple's badge service, which is what their
// marketing generator hands out; the artwork is not ours to redraw or host.
// It links to the listing id in lib/store.ts, a placeholder until the app
// is published, so until then the tap lands on the App Store's not-found.
const BADGE_SRC =
  "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&releaseDate=1735689600";

export default function AppStoreBadge({ height = 50 }: { height?: number }) {
  return (
    <a
      className={styles.badge}
      href={APP_STORE_URL}
      aria-label="Download on the App Store"
      style={{ height }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- remote SVG from Apple, sized by height */}
      <img src={BADGE_SRC} alt="" height={height} width={Math.round((height * 250) / 83)} />
    </a>
  );
}
