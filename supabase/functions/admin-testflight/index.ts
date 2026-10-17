import {
  type AdminContext,
  adminErrorResponse,
  AdminHttpError,
  adminRequestId,
  audit,
  authenticateAdmin,
  jsonResponse,
  readBoundedBody,
} from "../_shared/admin_auth.ts";
import { AppleClient, appleConfig } from "./apple.ts";
import {
  assertFounder,
  parseCommand,
  type TestFlightCommand,
} from "./contracts.ts";
import {
  AttemptError,
  type Claim,
  type Outcome,
  processRequest,
} from "./workflow.ts";

async function rpc(
  context: AdminContext,
  name: string,
  params: Record<string, unknown>,
) {
  const { data, error } = await context.db.rpc(name, {
    p_actor: context.actorId,
    ...params,
  });
  if (error) {
    throw new AdminHttpError(
      error.code === "P0002" ? 404 : error.code === "42501" ? 403 : 409,
      "The access request changed or is unavailable. Refresh and try again.",
    );
  }
  return data;
}
async function connection() {
  const config = appleConfig();
  if (!config) {
    return {
      ready: false,
      groupName: null,
      build: null,
      message: "App Store Connect credentials need setup.",
    };
  }
  try {
    return await new AppleClient(config).connection();
  } catch {
    return {
      ready: false,
      groupName: null,
      build: null,
      message:
        "Apple connection needs attention. Check the key and external testing group.",
    };
  }
}
async function perform(context: AdminContext, command: TestFlightCommand) {
  if (command.op === "connection") return await connection();
  if (command.op === "list") {
    const [page, provider] = await Promise.all([
      rpc(context, "admin_list_testflight_requests", {
        p_filter: command.filter,
        p_offset: command.offset,
        p_limit: 50,
      }),
      connection(),
    ]);
    await audit(
      context,
      "testflight.requests.read",
      "allowed",
      "access_requests",
      undefined,
      { filter: command.filter },
    );
    return { ...page, connection: provider };
  }
  const config = appleConfig();
  if (["invite", "sync"].includes(command.op) && !config) {
    throw new AdminHttpError(
      503,
      "App Store Connect needs setup before invitations can be managed.",
    );
  }
  // Check the destination before reserving a request. Never accept a group from the browser.
  const apple = config ? new AppleClient(config) : null;
  if (command.op === "invite") {
    try {
      await apple!.connection();
    } catch {
      throw new AdminHttpError(
        503,
        "Apple connection needs attention. The group must have an active external build.",
      );
    }
  }
  await audit(
    context,
    `testflight.${command.op}.requested`,
    "allowed",
    "access_request",
    command.id,
  );
  const claim = await rpc(context, "admin_claim_testflight_request", {
    p_id: command.id,
    p_action: command.op,
  });
  if (claim.busy) {
    throw new AdminHttpError(
      409,
      "This request is being checked. Wait two minutes before refreshing its status.",
    );
  }
  if (claim.done) {
    return {
      id: command.id,
      status: command.op === "archive" ? "archived" : "new",
    };
  }
  let outcome: Outcome;
  try {
    outcome = await processRequest(apple!, claim as Claim);
  } catch (error) {
    const attempt = error instanceof AttemptError
      ? error
      : new AttemptError(true, "unexpected_failure");
    outcome = {
      status: attempt.uncertain || !claim.maySend ? "uncertain" : "failed",
      testerId: claim.testerId,
      state: null,
      errorCode: attempt.code,
    };
  }
  const saved = await rpc(context, "admin_finish_testflight_request", {
    p_id: command.id,
    p_lease: claim.leaseId,
    p_status: outcome.status,
    p_tester: outcome.testerId,
    p_state: outcome.state,
    p_group: config!.groupId,
    p_error: outcome.errorCode,
  });
  if (!saved) {
    throw new AdminHttpError(
      409,
      "The invitation result needs a status refresh.",
    );
  }
  await audit(
    context,
    `testflight.${command.op}.result`,
    ["failed", "uncertain"].includes(outcome.status) ? "failed" : "allowed",
    "access_request",
    command.id,
    { status: outcome.status, providerCode: outcome.errorCode },
  );
  return {
    id: command.id,
    status: outcome.status,
    appleState: outcome.state,
    errorCode: outcome.errorCode,
  };
}
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  const requestId = adminRequestId(req);
  try {
    const raw = await readBoundedBody(req, 8192);
    const context = await authenticateAdmin(req, raw, "admin.read", {
      requestId,
      requireRecentTotp: true,
    });
    try {
      assertFounder(context.role);
    } catch {
      await audit(context, "testflight.access", "denied");
      throw new AdminHttpError(
        403,
        "Only the founder can manage access requests.",
      );
    }
    let command: TestFlightCommand;
    try {
      command = parseCommand(JSON.parse(raw));
    } catch {
      throw new AdminHttpError(400, "The request action is invalid.");
    }
    return jsonResponse(await perform(context, command));
  } catch (error) {
    return adminErrorResponse(error, requestId);
  }
});
