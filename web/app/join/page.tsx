import type { Metadata } from "next";
import JoinPage from "./JoinPage";

export const metadata: Metadata = {
  title: "Join a friend’s Table",
  description: "Share recipes, food finds, and dinner ideas with friends on Plated.",
  openGraph: {
    title: "Join a friend’s Table",
    description: "Share recipes, food finds, and dinner ideas with friends on Plated.",
  },
  // An invitation is addressed to one person. Search engines are not invited.
  robots: { index: false, follow: false },
  alternates: { canonical: "/join" },
};

// https://plated.food/join?s=<share>&h=<host>&i=<invite id>: a seat at
// somebody's Table. The household's own invitation is /join/household.
export default function Join() {
  return <JoinPage kind="table" />;
}
