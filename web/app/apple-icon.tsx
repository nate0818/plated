import { ImageResponse } from "next/og";

// The home-screen version of the favicon: the same dot, on a plate.
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
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
        <div
          style={{
            width: 132,
            height: 132,
            borderRadius: "50%",
            background: "#FFFFFF",
            border: "3px solid #F0EBE4",
            boxShadow: "inset 0 0 0 10px #FFFFFF, inset 0 0 0 12px #F7F3EE",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div style={{ width: 44, height: 44, borderRadius: "50%", background: "#FF5A3C" }} />
        </div>
      </div>
    ),
    size,
  );
}
