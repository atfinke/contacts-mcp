import { ensureHelperExists, runHelper } from "../src/helper.js";

type PermissionsPayload = {
  status: string;
  canRead: boolean;
  isLimited: boolean;
};

async function main(): Promise<void> {
  await ensureHelperExists();

  const permissions = await runHelper<PermissionsPayload>("permissions", {
    prompt: false,
  });

  console.log(JSON.stringify({ permissions }, null, 2));

  if (!permissions.canRead) {
    console.log("Skipping live lookups because Contacts access is not granted.");
    return;
  }

  const phoneQuery = process.env.CONTACTS_MCP_SMOKE_PHONE ?? "+19999999999";
  const emailQuery = process.env.CONTACTS_MCP_SMOKE_EMAIL ?? "nobody@example.invalid";
  const nameQuery = process.env.CONTACTS_MCP_SMOKE_NAME ?? "Nobody";

  const lookupPhone = await runHelper("lookup-phone", {
    query: phoneQuery,
    "max-results": 3,
  });

  const lookupEmail = await runHelper("lookup-email", {
    query: emailQuery,
    "max-results": 3,
  });

  const searchName = await runHelper("search-name", {
    query: nameQuery,
    "max-results": 3,
  });

  console.log(JSON.stringify({ lookupPhone, lookupEmail, searchName }, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  console.error(message);
  process.exit(1);
});
