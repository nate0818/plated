import type { Metadata } from "next";
import JoinPage from "./JoinPage";

export const metadata: Metadata = {
  title: "A seat at the table",
  description: "Someone kept you a seat at their table on Plated.",
  openGraph: {
    title: "A seat at the table",
    description: "Someone kept you a seat at their table on Plated.",
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
