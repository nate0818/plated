import { AppleError, type Resource } from "./apple.ts";
import { stateStatus } from "./contracts.ts";
export interface TesterProvider {
  find(email: string, groupOnly?: boolean): Promise<Resource | null>;
  create(email: string): Promise<Resource>;
  add(id: string): Promise<void>;
  invite(id: string): Promise<void>;
}
export interface Claim {
  leaseId: string;
  email: string;
  previousStatus: string;
  maySend: boolean;
  testerId: string | null;
}
export interface Outcome {
  status: string;
  testerId: string | null;
  state: string | null;
  errorCode: string | null;
}
export class AttemptError extends Error {
  constructor(public uncertain: boolean, public code: string) {
    super("The Apple request could not be completed.");
  }
}
export async function processRequest(
  apple: TesterProvider,
  claim: Claim,
): Promise<Outcome> {
  let changed = false;
  let writing = false;
  const write = async <T>(fn: () => Promise<T>) => {
    writing = true;
    const result = await fn();
    writing = false;
    changed = true;
    return result;
  };
  try {
    let tester = await apple.find(claim.email, true);
    if (!tester && !claim.maySend) {
      return {
        status: ["new", "failed"].includes(claim.previousStatus)
          ? claim.previousStatus
          : "uncertain",
        testerId: claim.testerId,
        state: null,
        errorCode: "not_in_group",
      };
    }
    if (!tester) {
      tester = await apple.find(claim.email);
      if (tester) {
        await write(() => apple.add(tester!.id));
        tester = await apple.find(claim.email, true);
      } else tester = await write(() => apple.create(claim.email));
    }
    if (!tester) throw new AttemptError(changed, "tester_lookup_failed");
    const state = typeof tester.attributes?.state === "string"
      ? tester.attributes.state
      : undefined;
    const known = stateStatus(state);
    if (known) {
      return {
        status: known,
        testerId: tester.id,
        state: state!,
        errorCode: null,
      };
    }
    if (!claim.maySend) {
      return {
        status: "uncertain",
        testerId: tester.id,
        state: state ?? null,
        errorCode: "invitation_unconfirmed",
      };
    }
    // Unknown provider states must never cause an email. NOT_INVITED is explicit.
    if (state !== "NOT_INVITED") {
      throw new AttemptError(changed, "unknown_apple_state");
    }
    await write(() => apple.invite(tester!.id));
    return {
      status: "invited",
      testerId: tester.id,
      state: "INVITED",
      errorCode: null,
    };
  } catch (error) {
    if (error instanceof AttemptError) throw error;
    const uncertain = changed ||
      (writing && (!(error instanceof AppleError) || error.uncertain));
    throw new AttemptError(
      uncertain,
      error instanceof AppleError
        ? `apple_${error.status || "timeout"}`
        : "apple_unavailable",
    );
  }
}
