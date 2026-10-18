import AppShowcase from "./AppShowcase";
import styles from "./HouseholdPreview.module.css";

/** Genuine app capture with context from the clearly labeled sample household. */
export default function HouseholdPreview() {
  return <div className={styles.preview} data-depth>
    <div className={styles.heading}><span className={styles.avatar} aria-hidden="true">S</span><div><p>Sam’s making pizza tomorrow</p><span>Everyone knows the plan</span></div></div>
    <div className={styles.phone} data-depth-item><AppShowcase screen="plan" appearance="light" compact capture={{ src: "/app/plan-sam-light-818.png", alt: "Plated’s shared dinner plan with Pizza Night assigned to Sam" }} /></div>
    <p className={styles.caption}>Real app screen · Example household</p>
  </div>;
}
