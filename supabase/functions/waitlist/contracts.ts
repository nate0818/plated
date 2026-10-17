export const EARLY_ACCESS_SOURCE = "plated.food/early-access";
export function emailPattern(email: string): string {
  // ilike must match the literal address, including valid % and _ characters.
  return email.replace(/[\\%_]/g, "\\$&");
}
