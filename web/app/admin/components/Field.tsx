import styles from "../admin.module.css";

/// Fields whose label sits inside them and rises out of the way once there is
/// something to read. The label element wraps its control, so the whole field
/// is a click target and a screen reader still hears the name, and the filled
/// state is read from :placeholder-shown rather than React state, so a browser
/// autofilling before React hears about it still lands in the right place.
///
/// The control gets its own positioning box. Without it the label centres on
/// the whole field, and any field carrying help text underneath drew its
/// label below its own input.
///
/// `trailing` sits inside the control box, for a character counter.
/// `help` sits under the field, for a sentence about it.
/// `wrapperClassName` styles the field (grid span); `className` the control.

type Common = {
  label: string;
  trailing?: React.ReactNode;
  help?: React.ReactNode;
  wrapperClassName?: string;
};

function field(wrapperClassName?: string, extra?: string) {
  return [styles.floatField, extra, wrapperClassName].filter(Boolean).join(" ");
}

function control(className?: string, extra?: string) {
  return [styles.floatInput, extra, className].filter(Boolean).join(" ");
}

export default function Field({
  label,
  trailing,
  help,
  className,
  wrapperClassName,
  placeholder = " ",
  ...props
}: Common & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className={field(wrapperClassName)}>
      <span className={styles.floatControl}>
        <input {...props} placeholder={placeholder} className={control(className)} />
        <span className={styles.floatLabel}>{label}</span>
        {trailing}
      </span>
      {help}
    </label>
  );
}

export function FieldArea({
  label,
  trailing,
  help,
  className,
  wrapperClassName,
  placeholder = " ",
  ...props
}: Common & React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <label className={field(wrapperClassName, styles.floatFieldArea)}>
      <span className={styles.floatControl}>
        <textarea {...props} placeholder={placeholder} className={control(className, styles.floatArea)} />
        <span className={styles.floatLabel}>{label}</span>
        {trailing}
      </span>
      {help}
    </label>
  );
}

/// A select always has a value, so its label is never in the resting
/// position: it starts raised and stays there.
export function FieldSelect({
  label,
  trailing,
  help,
  className,
  wrapperClassName,
  children,
  ...props
}: Common & React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <label className={field(wrapperClassName, styles.floatFieldSelect)}>
      <span className={styles.floatControl}>
        <select {...props} className={control(className, styles.floatSelect)}>
          {children}
        </select>
        <span className={styles.floatLabel}>{label}</span>
        {trailing}
      </span>
      {help}
    </label>
  );
}
