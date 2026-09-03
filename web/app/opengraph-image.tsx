import { ImageResponse } from "next/og";

// The card that appears when plated.food is pasted into Messages, Slack or a
// tweet. Rendered at build time, so it never drifts from the copy on the
// page. Gabarito is fetched from Google Fonts for the render; if that fetch
// ever fails the card still builds in the system face rather than failing
// the deploy over a font.
export const alt = "Plated: a week of dinners, planned together. Coming to iPhone and iPad.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

async function gabarito(): Promise<ArrayBuffer | null> {
  try {
    // A user agent Google does not recognise gets the plain TTF, which is
    // what ImageResponse can read. A browser-shaped one gets woff2, which
    // it cannot, and an old-Firefox one gets woff. Measured, not assumed.
    const css = await fetch("https://fonts.googleapis.com/css2?family=Gabarito:wght@500", {
      headers: { "User-Agent": "plated.food opengraph-image" },
    }).then((r) => r.text());
    const url = css.match(/src: url\((.+?)\) format\('(truetype|opentype|woff)'\)/)?.[1];
    if (!url) return null;
    return await fetch(url).then((r) => r.arrayBuffer());
  } catch {
    return null;
  }
}

export default async function OpenGraphImage() {
  const font = await gabarito();
  const display = font ? "Gabarito" : "system-ui, sans-serif";

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#FFFFFF",
          color: "#221B14",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "72px 84px",
          fontFamily: display,
        }}
      >
        <div style={{ display: "flex", alignItems: "flex-start", fontSize: 56, letterSpacing: "-0.022em", fontWeight: 500 }}>
          plated
          <div style={{ width: 15, height: 15, borderRadius: "50%", background: "#FF5A3C", marginTop: 19, marginLeft: 6 }} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 28 }}>
          <div style={{ fontSize: 112, lineHeight: 0.98, letterSpacing: "-0.03em", fontWeight: 500, display: "flex", flexDirection: "column" }}>
            <span>A week of dinners,</span>
            <span>planned together.</span>
          </div>
          <div style={{ fontSize: 34, color: "#7F7364", fontFamily: "system-ui, sans-serif", fontWeight: 500 }}>
            Coming to iPhone and iPad
          </div>
        </div>
      </div>
    ),
    {
      ...size,
      fonts: font ? [{ name: "Gabarito", data: font, weight: 500, style: "normal" }] : undefined,
    },
  );
}
