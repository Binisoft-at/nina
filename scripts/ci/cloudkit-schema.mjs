// Imports cloudkit/schema.ckdb into the Development environment of the app's own container with
// Apple's CKTool JS (Linux, no Mac minutes), then exports Development and Production so the report
// says whether Production still needs "Deploy Schema Changes…" (a button in the CloudKit Console –
// Apple has no API for that step).
//
// Env: CLOUDKIT_MANAGEMENT_TOKEN, APPLE_TEAM_ID, CONTAINER_ID (from Config/Base.xcconfig),
//      SCHEMA_FILE (default cloudkit/schema.ckdb), OUT_DIR (default ci-logs/cloudkit), DRY_RUN=1 (validate only)
// Needs: npm install @apple/cktool.database @apple/cktool.target.nodejs (the workflow does it).
// Synced from the Binisoft handbook.
import fs from "node:fs";
import path from "node:path";
import database from "@apple/cktool.database";
import target from "@apple/cktool.target.nodejs";

const { PromisesApi, CKEnvironment } = database;
const { createConfiguration } = target;

const token = process.env.CLOUDKIT_MANAGEMENT_TOKEN;
const teamId = process.env.APPLE_TEAM_ID;
const containerId = process.env.CONTAINER_ID;
const schemaPath = process.env.SCHEMA_FILE || "cloudkit/schema.ckdb";
const outDir = process.env.OUT_DIR || "ci-logs/cloudkit";
fs.mkdirSync(outDir, { recursive: true });

const report = [];
const log = (line) => { console.log(line); report.push(line); };
const finish = (code) => {
  fs.writeFileSync(path.join(outDir, "report.txt"), report.join("\n") + "\n");
  process.exit(code);
};

if (!token || !teamId || !containerId) {
  log("Missing CLOUDKIT_MANAGEMENT_TOKEN, APPLE_TEAM_ID or CONTAINER_ID.");
  finish(1);
}

const api = new PromisesApi({ configuration: createConfiguration(), security: { ManagementTokenAuth: token } });
const text = fs.readFileSync(schemaPath, "utf8");
const schemaFile = () => new File([text], "schema.ckdb", { type: "text/plain" });
const scope = (environment) => ({ teamId, containerId, environment });

function describe(error) {
  if (!error) return "unknown error";
  const parts = [error.name, error.message];
  for (const key of ["statusCode", "status", "response", "result", "body", "data", "errors"]) {
    if (error[key] !== undefined) parts.push(`${key}: ${JSON.stringify(error[key], null, 2)}`);
  }
  return parts.filter(Boolean).join("\n");
}

async function exportSchema(environment, file) {
  const exported = await api.exportSchema(scope(environment));
  let body = exported?.result ?? exported;
  if (body && typeof body.text === "function") body = await body.text();
  else if (body && typeof body === "object") body = JSON.stringify(body, null, 2);
  fs.writeFileSync(path.join(outDir, file), String(body ?? ""));
  return String(body ?? "");
}

// Record types and fields only, so formatting differences don't count.
function shape(schema) {
  return schema.split("\n")
    .map((line) => line.trim().replace(/,$/, ""))
    .filter((line) => /^RECORD TYPE|^"?[A-Za-z_][A-Za-z0-9_.]*"?\s+(STRING|INT64|DOUBLE|TIMESTAMP|REFERENCE|BYTES|ENCRYPTED|ASSET|LOCATION|LIST)/.test(line))
    .map((line) => line.replace(/\s+/g, " ").replace(/ (QUERYABLE|SORTABLE|SEARCHABLE)/g, ""))
    .sort();
}

// "RecordType.field" for every record type and field (system fields left out), so the check
// doesn't depend on how a file is formatted.
function fields(schema) {
  const keys = new Set();
  let type = null;
  for (const raw of schema.split("\n")) {
    const line = raw.trim().replace(/,$/, "");
    const record = line.match(/^RECORD TYPE\s+"?([A-Za-z_][A-Za-z0-9_.]*)"?/);
    if (record) { type = record[1]; keys.add(type); continue; }
    if (line.startsWith(")")) { type = null; continue; }
    const field = line.match(/^"?([A-Za-z_][A-Za-z0-9_.]*)"?\s+(STRING|INT64|DOUBLE|TIMESTAMP|REFERENCE|BYTES|ENCRYPTED|ASSET|LOCATION|LIST)/);
    if (type && field && !field[1].startsWith("___")) keys.add(`${type}.${field[1]}`);
  }
  return keys;
}

// CHECK_PRODUCTION=1 (the TestFlight workflow, before archiving): every record type and field of
// the schema file must already be in Production – a build that writes a field Production doesn't
// have can't upload anything. Production may have more (fields no longer used stay there). Fails
// only when something is clearly missing; when Production can't be read it warns and passes, so a
// tool hiccup never blocks a release.
if (process.env.CHECK_PRODUCTION === "1") {
  let production;
  try {
    production = await exportSchema(CKEnvironment.PRODUCTION, "production.ckdb");
  } catch (error) {
    log(`WARNING: the Production schema couldn't be read (${error.message}) – not checked.`);
    finish(0);
  }
  const have = fields(production);
  const missing = [...fields(text)].filter((key) => !have.has(key)).sort();
  if (missing.length === 0) {
    log(`Production of ${containerId} has every record type and field of ${schemaPath}.`);
    finish(0);
  }
  log(`Deploy the CloudKit schema first: https://icloud.developer.apple.com/dashboard → CloudKit Database → ${containerId} → Development → Deploy Schema Changes… → Deploy`);
  log(`Missing in Production: ${missing.join(", ")}`);
  fs.writeFileSync(path.join(outDir, "schema-check.errors.txt"), report.join("\n") + "\n");
  finish(1);
}

try {
  log(`Validating ${schemaPath} against ${containerId} (Development)…`);
  const validation = await api.validateSchema({ ...scope(CKEnvironment.DEVELOPMENT), file: schemaFile() });
  log(`Validation: ${JSON.stringify(validation?.result ?? validation ?? "ok", null, 2)}`);
  if (process.env.DRY_RUN === "1") finish(0);

  log("Importing into Development…");
  const imported = await api.importSchema({ ...scope(CKEnvironment.DEVELOPMENT), file: schemaFile() });
  log(`Import: ${JSON.stringify(imported?.result ?? imported ?? "ok", null, 2)}`);

  const development = await exportSchema(CKEnvironment.DEVELOPMENT, "development.ckdb");
  let production = "";
  try {
    production = await exportSchema(CKEnvironment.PRODUCTION, "production.ckdb");
  } catch (error) {
    log(`Production schema not readable yet: ${error.message}`);
  }
  const same = production && JSON.stringify(shape(development)) === JSON.stringify(shape(production));
  log(same
    ? "Production already matches Development – nothing to deploy."
    : `NEXT: CloudKit Console → ${containerId} → Development → Deploy Schema Changes… → Deploy (before the next TestFlight build).`);
  fs.writeFileSync(path.join(outDir, "needs-deploy.txt"), same ? "no\n" : "yes\n");
  finish(0);
} catch (error) {
  log(`FAILED:\n${describe(error)}`);
  finish(1);
}
