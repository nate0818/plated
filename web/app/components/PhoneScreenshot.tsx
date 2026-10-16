import Image from "next/image";
import styles from "./PhoneScreenshot.module.css";

export type AppScreen = "plan" | "recipes" | "groceries" | "table";
export const screenImages: Record<AppScreen, string> = {
  plan: "/app/editorial-plan-current.png",
  recipes: "/app/editorial-recipes-current.png",
  groceries: "/app/editorial-groceries-current.png",
  table: "/app/editorial-table-current.png",
};
export const screenDescriptions: Record<AppScreen, string> = {
  plan: "Plated’s Plan screen with Week and Month controls, the date wheel, Salmon Night, and an assigned cook",
  recipes: "Plated’s Recipes screen with searchable saved recipes including pancakes, lemon butter salmon, and poke bowls",
  groceries: "Plated’s Editorial Groceries screen with a shopping window, pantry controls, and a Reminders action",
  table: "Plated’s private Table screen with an invite-only audience and a pancake dinner shared with friends",
};

export default function PhoneScreenshot({ screen, priority = false }: { screen: AppScreen; priority?: boolean }) {
  return <div className={styles.phone}><Image src={screenImages[screen]} alt={screenDescriptions[screen]} width={800} height={1739} sizes="(max-width: 600px) 48vw, 300px" priority={priority} loading={priority ? "eager" : "lazy"} className={styles.screen} /></div>;
}
