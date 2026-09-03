import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: "https://plated.food", lastModified: new Date("2026-09-03"), changeFrequency: "weekly", priority: 1 },
    { url: "https://plated.food/privacy", lastModified: new Date("2026-09-03"), changeFrequency: "yearly", priority: 0.3 },
  ];
}
