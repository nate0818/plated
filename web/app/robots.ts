import type { MetadataRoute } from "next";

// The homepage and the privacy page are for finding. The invitation pages are
// each addressed to one person and the API is not a page at all.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{
      userAgent: "*",
      allow: "/",
      disallow: ["/join", "/join/household", "/api/", "/admin", "/admin/"],
    }],
    sitemap: "https://plated.food/sitemap.xml",
    host: "https://plated.food",
  };
}
