import { promises as fs } from "fs";
import path from "path";
import postgres from "postgres";

const DATA_FILE = path.join(process.cwd(), "data", "waitlist.json");
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const MAX_BODY_BYTES = 16 * 1024;

// Table name comes from env so it can differ per app sharing one database.
// Strictly validated — anything else falls back to "waitlist".
function tableName(): string {
  const raw = (process.env.WAITLIST_TABLE || "waitlist").trim();
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(raw) ? raw : "waitlist";
}

function isEmail(v: unknown): v is string {
  if (typeof v !== "string") return false;
  const s = v.trim();
  if (s.length < 3 || s.length > 254) return false;
  if (s.includes("..") || s.includes(" ")) return false;
  if (!EMAIL_RE.test(s)) return false;
  const parts = s.split("@");
  if (parts.length !== 2) return false;
  const [local, domain] = parts;
  if (!local || !domain) return false;
  if (local.startsWith(".") || local.endsWith(".")) return false;
  if (domain.startsWith(".") || domain.endsWith(".")) return false;
  if (domain.startsWith("-") || domain.endsWith("-")) return false;
  if (domain.includes("_")) return false;
  const labels = domain.split(".");
  if (labels.some((l) => l.length === 0 || l.length > 63)) return false;
  const tld = labels[labels.length - 1];
  if (tld.length < 2) return false;
  return true;
}

type LocalEntry = { email: string; source: string; created_at: string };

async function readLocal(): Promise<LocalEntry[]> {
  try {
    const raw = await fs.readFile(DATA_FILE, "utf8");
    const j = JSON.parse(raw);
    if (!Array.isArray(j)) return [];
    // Tolerate the old string[] format.
    return j
      .map((x) =>
        typeof x === "string"
          ? { email: x, source: "", created_at: new Date(0).toISOString() }
          : x,
      )
      .filter((x) => typeof x?.email === "string");
  } catch {
    return [];
  }
}

async function writeLocal(entries: LocalEntry[]) {
  await fs.mkdir(path.dirname(DATA_FILE), { recursive: true });
  await fs.writeFile(DATA_FILE, JSON.stringify(entries, null, 2));
}

// Same shape as shipyard-web: id SERIAL PK, unique email, source, timestamp.
async function ensureTable(
  sql: ReturnType<typeof postgres>,
  table: string,
) {
  await sql.unsafe(`CREATE TABLE IF NOT EXISTS ${table} (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    source TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`);
}

function dbUrl(): string {
  return (
    process.env.DATABASE_URL ||
    process.env.NEON_DATABASE_URL ||
    process.env.LOCAL_DATABASE_URL ||
    ""
  );
}

// Local Postgres (docker-compose) runs without SSL; Neon requires it.
// Infer like shipyard-web: neon.tech URL or sslmode=require means SSL.
function sqlFor(url: string) {
  const needsSsl =
    url.includes("neon.tech") ||
    url.includes("sslmode=require") ||
    url.includes("sslmode=verify-ca") ||
    url.includes("sslmode=verify-full");
  return needsSsl ? postgres(url, { ssl: "require" }) : postgres(url);
}

export async function GET() {
  // Prod path: Postgres / Neon via DATABASE_URL (provider inferred,
  // same as shipyard-web — neon.tech URL means Neon).
  if (dbUrl()) {
    const table = tableName();
    const sql = sqlFor(dbUrl());
    try {
      await ensureTable(sql, table);
      const rows =
        await sql.unsafe(`SELECT count(*)::int AS c FROM ${table}`);
      return Response.json({ count: rows[0].c, backend: "postgres", table });
    } finally {
      await sql.end();
    }
  }
  // Local dev path: JSON file, no infra.
  const entries = await readLocal();
  return Response.json({
    count: entries.length,
    backend: "file",
    table: tableName(),
  });
}

export async function POST(req: Request) {
  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).length > MAX_BODY_BYTES) {
    return Response.json(
      { ok: false, error: "Request payload too large." },
      { status: 413 },
    );
  }

  let payload: { email?: unknown; source?: unknown };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return Response.json(
      { ok: false, error: "Invalid JSON body." },
      { status: 400 },
    );
  }

  const email = String(payload.email || "").trim().toLowerCase();
  const source = String(payload.source || "").trim().slice(0, 64);
  if (!isEmail(email)) {
    return Response.json(
      { ok: false, error: "Enter a valid email address." },
      { status: 400 },
    );
  }

  if (dbUrl()) {
    const table = tableName();
    const sql = sqlFor(dbUrl());
    try {
      await ensureTable(sql, table);
      const rows = await sql.unsafe(
        `INSERT INTO ${table} (email, source) VALUES ($1, $2)
         ON CONFLICT (email) DO NOTHING RETURNING id`,
        [email, source],
      );
      const duplicate = rows.length === 0;
      const count =
        (await sql.unsafe(`SELECT count(*)::int AS c FROM ${table}`))[0].c;
      return Response.json(
        { ok: true, duplicate, count, backend: "postgres", table },
        { status: duplicate ? 200 : 201 },
      );
    } finally {
      await sql.end();
    }
  }

  const entries = await readLocal();
  const duplicate = entries.some((e) => e.email === email);
  if (!duplicate) {
    entries.push({
      email,
      source,
      created_at: new Date().toISOString(),
    });
    await writeLocal(entries);
  }
  return Response.json(
    {
      ok: true,
      duplicate,
      count: entries.length,
      backend: "file",
      table: tableName(),
    },
    { status: duplicate ? 200 : 201 },
  );
}
