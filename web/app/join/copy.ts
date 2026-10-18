// The two invitations plated.food can carry, and what each one says.
//
// A Table link and a household link land on the same page shape, but they
// are invitations to different rooms: a Table guest sees what people cook
// and never the plan; a household member sees the plan, the grocery list
// and the cookbook and can change them. The copy has to say which, because
// the page is the only thing a person without the app ever reads before
// deciding to install it. docs/household.md section 1 draws the line.
//
// Plain data, no React, so both the server Fallback and the client
// Invitation can read it without crossing the server boundary.

export type Kind = "table" | "household";

export interface Copy {
  /// The two lines of the title when the host's name is known. The name
  /// itself is rendered by the page, in tomato, before `titleAfterName`.
  titleAfterName: [string, string];
  /// The title when the link carries no name.
  titleAnonymous: [string, string];
  lede: (host: string) => string;
  facts: { lead: string; rest: string }[];
}

export const COPY: Record<Kind, Copy> = {
  table: {
    titleAfterName: ["invited you", "to their Table"],
    titleAnonymous: ["You’re invited", "to a Table"],
    // "What they cook", never "the week ahead": a seat at the Table does not
    // come with the plan, and this page must not promise it.
    lede: (host) =>
      `Share recipes, food finds, and dinner ideas with ${host || "a friend"} on Plated.`,
    facts: [
      {
        lead: "Share with friends",
        rest: "at your invite-only Table.",
      },
      {
        lead: "Install Plated,",
        rest: "then open this invitation again to join.",
      },
      {
        lead: "Sign in with Apple",
        rest: "to get started.",
      },
    ],
  },
  household: {
    titleAfterName: ["invited you", "to their household"],
    titleAnonymous: ["You’re invited", "to a household"],
    lede: () =>
      "Plan meals, take turns cooking, and share a grocery list. Keep everyone at home in the dinner plan.",
    facts: [
      {
        lead: "Plan meals together",
        rest: "with a shared recipe book and grocery list.",
      },
      {
        lead: "Install Plated,",
        rest: "then open this invitation again to join.",
      },
      {
        lead: "Sign in with Apple",
        rest: "to get started.",
      },
    ],
  },
};

// A CloudKit record name or a TableInvites entry id. Nothing else belongs in
// the seat or invite slot of an app link, so anything else is dropped rather
// than forwarded.
const RECORD_NAME = /^[A-Za-z0-9_-]{1,80}$/;

export function recordName(raw: string | null): string {
  const value = (raw ?? "").trim();
  return RECORD_NAME.test(value) ? value : "";
}

// The app's own road for a phone that already has Plated, offered for the
// window before Apple has fetched the association file. It carries what the
// Universal Link carries: the kind, the seat (household) or the invite id
// (Table), and the host's name. The raw iCloud link would open the share and
// lose all three, and a seatless join makes the joiner pick a seat by hand.
//
// Built by hand rather than with URLSearchParams, which spells a space as
// "+"; the app reads the query with URLComponents, which keeps a "+" as a
// plus, and "Mary Ann" must arrive as Mary Ann.
export function appLink(
  kind: Kind,
  share: string,
  extras: { seat?: string; invite?: string; host?: string },
): string {
  const items: [string, string][] = [
    ["s", share],
    ["k", kind],
  ];
  if (kind === "household" && extras.seat) items.push(["seat", extras.seat]);
  if (kind === "table" && extras.invite) items.push(["i", extras.invite]);
  if (extras.host) items.push(["h", extras.host]);
  return (
    "plated://join?" +
    items.map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&")
  );
}
