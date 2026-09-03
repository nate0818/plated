import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Apple fetches the association file with no extension and does not follow
  // redirects. Vercel serves it from public/ as-is; this fixes the type it is
  // served with, which is the reason GitHub Pages was rejected for the job.
  async headers() {
    return [
      {
        source: "/.well-known/apple-app-site-association",
        headers: [
          { key: "Content-Type", value: "application/json" },
          { key: "Cache-Control", value: "public, max-age=3600" },
        ],
      },
    ];
  },
};

export default nextConfig;
