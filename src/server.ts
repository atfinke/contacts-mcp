import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { ensureHelperExists, jsonTextResult, runHelper } from "./helper.js";
import {
  normalizeContactIdentifier,
  normalizeEmailLookupInput,
  normalizeNameLookupInput,
  normalizePhoneLookupInput,
} from "./input.js";
import { APP_NAME, APP_VERSION } from "./meta.js";

const lookupInputSchema = {
  maxResults: z.number().int().positive().max(25).optional(),
};

export function createServer(): McpServer {
  const server = new McpServer({
    name: APP_NAME,
    version: APP_VERSION,
  });

  server.registerTool(
    "contacts_permissions",
    {
      title: "Contacts Permissions",
      description: "Check and optionally prompt for Apple Contacts access used by the helper app.",
      inputSchema: {
        prompt: z.boolean().optional(),
      },
    },
    async ({ prompt }) => {
      await ensureHelperExists();
      const result = await runHelper("permissions", {
        prompt: prompt ?? false,
      });

      return jsonTextResult(result);
    },
  );

  server.registerTool(
    "contacts_lookup_phone",
    {
      title: "Lookup Phone",
      description:
        "Resolve one phone number to matching Apple Contacts entries. Returns zero or more ranked matches.",
      annotations: {
        readOnlyHint: true,
      },
      inputSchema: {
        phoneNumber: z.string(),
        ...lookupInputSchema,
      },
    },
    async ({ phoneNumber, maxResults }) => {
      const normalizedPhoneNumber = normalizePhoneLookupInput(phoneNumber);
      await ensureHelperExists();

      const result = await runHelper("lookup-phone", {
        query: normalizedPhoneNumber,
        "max-results": maxResults ?? 10,
      });

      return jsonTextResult(result);
    },
  );

  server.registerTool(
    "contacts_lookup_email",
    {
      title: "Lookup Email",
      description:
        "Resolve one email address to matching Apple Contacts entries. Returns zero or more ranked matches.",
      annotations: {
        readOnlyHint: true,
      },
      inputSchema: {
        emailAddress: z.string(),
        ...lookupInputSchema,
      },
    },
    async ({ emailAddress, maxResults }) => {
      const normalizedEmailAddress = normalizeEmailLookupInput(emailAddress);
      await ensureHelperExists();

      const result = await runHelper("lookup-email", {
        query: normalizedEmailAddress,
        "max-results": maxResults ?? 10,
      });

      return jsonTextResult(result);
    },
  );

  server.registerTool(
    "contacts_search_name",
    {
      title: "Search Name",
      description:
        "Search Apple Contacts by name, nickname, or organization. Returns zero or more ranked matches.",
      annotations: {
        readOnlyHint: true,
      },
      inputSchema: {
        nameQuery: z.string(),
        ...lookupInputSchema,
      },
    },
    async ({ nameQuery, maxResults }) => {
      const normalizedNameQuery = normalizeNameLookupInput(nameQuery);
      await ensureHelperExists();

      const result = await runHelper("search-name", {
        query: normalizedNameQuery,
        "max-results": maxResults ?? 10,
      });

      return jsonTextResult(result);
    },
  );

  server.registerTool(
    "contacts_get_contact",
    {
      title: "Get Contact",
      description: "Fetch one Apple Contact by unified contact identifier.",
      annotations: {
        readOnlyHint: true,
      },
      inputSchema: {
        contactIdentifier: z.string(),
      },
    },
    async ({ contactIdentifier }) => {
      const normalizedContactIdentifier = normalizeContactIdentifier(contactIdentifier);
      await ensureHelperExists();

      const result = await runHelper("get-contact", {
        "contact-identifier": normalizedContactIdentifier,
      });

      return jsonTextResult(result);
    },
  );

  return server;
}
