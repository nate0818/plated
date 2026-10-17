import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: "https://plated.food", lastModified: new Date("2026-10-17"), changeFrequency: "weekly", priority: 1 },
    { url: "https://plated.food/early-access", lastModified: new Date("2026-10-17"), changeFrequency: "monthly", priority: 0.6 },
    { url: "https://plated.food/privacy", lastModified: new Date("2026-10-17"), changeFrequency: "yearly", priority: 0.3 },
  ];
}
