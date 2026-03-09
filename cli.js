#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

if (process.platform !== "darwin") {
  console.error("Error: このツールは macOS 専用です。");
  process.exit(1);
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const script = join(__dirname, "bin", "fix.sh");
const args = process.argv.slice(2);

try {
  execFileSync("bash", [script, ...args], { stdio: "inherit" });
} catch (e) {
  process.exit(e.status ?? 1);
}
