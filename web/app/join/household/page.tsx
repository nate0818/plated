import type { Metadata } from "next";
import JoinPage from "../JoinPage";

export const metadata: Metadata = {
  title: "An invitation to a household",
  description: "Someone invited you to their household on Plated.",
  openGraph: {
    title: "An invitation to a household",
    description: "Someone invited you to their household on Plated.",
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
