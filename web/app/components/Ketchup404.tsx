import SiteFrame from "./SiteFrame";
import Ketchup404Scene from "./Ketchup404Scene";
import styles from "./Ketchup404.module.css";

export default function Ketchup404() {
  return (
    <SiteFrame action="home">
      <main id="main" className={styles.main}>
        <Ketchup404Scene />
      </main>
    </SiteFrame>
  );
}
