import styles from "../admin.module.css";

/// A text field whose label sits inside it and rises when the field has
/// something in it. The wrapping label element keeps the whole field
/// clickable and keeps the accessible name; the space in `placeholder` is
/// what lets CSS tell an empty field from a filled one.
export default function Field({
  label,
  className,
  ...props
}: { label: string } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className={styles.floatField}>
      <input
        {...props}
        placeholder=" "
        className={className ? `${styles.floatInput} ${className}` : styles.floatInput}
      />
      <span className={styles.floatLabel}>{label}</span>
    </label>
  );
}
