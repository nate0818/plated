import type { Metadata } from "next";
import Ketchup404 from "../components/Ketchup404";

export const metadata: Metadata = {
  title: "Page not found",
  robots: { index: false, follow: false },
};

export default function KetchupPreview() {
  return <Ketchup404 />;
}
