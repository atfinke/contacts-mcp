import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { APP_NAME } from "./meta.js";
import { createServer } from "./server.js";

async function main(): Promise<void> {
  const server = createServer();
  const transport = new StdioServerTransport();

  await server.connect(transport);
  console.error(`${APP_NAME} server is running on stdio`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  console.error(message);
  process.exit(1);
});
