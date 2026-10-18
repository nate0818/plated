"use client";

import { useId, useState } from "react";
import styles from "./direction.module.css";

export default function DirectionQuestions({ questions }: { questions: readonly (readonly [string, string])[] }) {
  const [open, setOpen] = useState<number | null>(null);
  const id = useId();

  return <div className={styles.questionList}>
    {questions.map(([question, answer], index) => {
      const expanded = open === index;
      return <div className={styles.question} key={question}>
        <h3><button type="button" id={`${id}-question-${index}`} aria-expanded={expanded} aria-controls={`${id}-answer-${index}`} onClick={() => setOpen(expanded ? null : index)}>
          {question}<span data-open={expanded} aria-hidden="true">+</span>
        </button></h3>
        <div className={styles.answer} id={`${id}-answer-${index}`} role="region" aria-labelledby={`${id}-question-${index}`} aria-hidden={!expanded} inert={!expanded} data-open={expanded}>
          <div><p>{answer}</p></div>
        </div>
      </div>;
    })}
  </div>;
}
