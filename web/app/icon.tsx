import { ImageResponse } from "next/og";

// Plated has no logo badge, and a favicon is not the place to invent one.
// This is the wordmark's dot: tomato on canvas, the one always-tomato thing.
export const size = { width: 64, height: 64 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#FFFFFF",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div style={{ width: 34, height: 34, borderRadius: "50%", background: "#FF5A3C" }} />
      </div>
    ),
    size,
  );
}
