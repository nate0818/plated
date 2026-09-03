// The App Store glyph, drawn in ink so it sits in the eyebrow as a word
// would. The coloured "Download on the App Store" badge is Apple's, has to
// point at a live listing, and replaces this the day the listing exists.
export default function AppStoreMark({ size = 18 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="2" y="2" width="20" height="20" rx="5.5" />
      <path d="M6.6 15.4h10.8" />
      <path d="M8.9 15.4 12 9.4l3.1 6" />
      <path d="M12 9.4 10.9 7.3" />
      <path d="M8.9 15.4 7.9 17.3" />
    </svg>
  );
}
