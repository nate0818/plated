import type { Metadata } from "next";
import JoinPage from "../JoinPage";

export const metadata: Metadata = {
  title: "Join a household",
  description: "Plan meals, see who’s cooking, and share a grocery list with your household on Plated.",
  openGraph: {
    title: "Join a household",
    description: "Plan meals, see who’s cooking, and share a grocery list with your household on Plated.",
  },
  // An invitation is addressed to one person. Search engines are not invited.
  robots: { index: false, follow: false },
  alternates: { canonical: "/join/household" },
};

// https://plated.food/join/household?s=<share>&h=<host>&seat=<seat>: a place
// in somebody's household, which is the plan, the grocery list and the
// cookbook. Distinct from /join, a seat at their Table, which is none of
// those. docs/household.md sections 6 and 7.
export default function JoinHousehold() {
  return <JoinPage kind="household" />;
}
