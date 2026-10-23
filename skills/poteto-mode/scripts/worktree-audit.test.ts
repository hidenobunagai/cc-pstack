import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { Database } from "bun:sqlite";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

interface AuditRow {
  size: string;
  age: string;
  merged: string;
  dirty: string;
  remote: string;
  pr: string;
  lastChat: string;
  bucket: string;
  worktree: string;
}

function parseAuditOutput(output: string): AuditRow[] {
  const lines = output.trim().split("\n");
  const rows: AuditRow[] = [];
  for (const line of lines) {
    if (line.startsWith("#") || line.startsWith("SIZE\t") || !line.trim()) {
      continue;
    }
    const parts = line.split("\t");
    if (parts.length >= 9) {
      rows.push({
        size: parts[0],
        age: parts[1],
        merged: parts[2],
        dirty: parts[3],
        remote: parts[4],
        pr: parts[5],
        lastChat: parts[6],
        bucket: parts[7],
        worktree: parts[8],
      });
    }
  }
  return rows;
}

const auditScript = path.resolve(__dirname, "worktree-audit.sh");

describe("worktree-audit", () => {
  let tempDir: string;
  let homeDir: string;
  let repoDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "audit-test-"));
    homeDir = path.join(tempDir, "home");
    repoDir = path.join(tempDir, "repo");
    fs.mkdirSync(homeDir, { recursive: true });
    fs.mkdirSync(repoDir, { recursive: true });

    spawnSync("jj", ["git", "init", "--colocate", repoDir], { check: true });
    spawnSync("jj", ["new", "-m", "initial commit"], { cwd: repoDir, check: true });
    spawnSync("jj", ["bookmark", "set", "main", "-r", "@"], { cwd: repoDir, check: true });
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  function createWorkspace(name: string, revset = "main"): string {
    const wtPath = path.join(tempDir, name);
    spawnSync("jj", ["workspace", "add", wtPath, "-r", revset], {
      cwd: repoDir,
      check: true,
    });
    return wtPath;
  }

  function initAgyDb(
    records: Array<{
      conversationId: string;
      lastModifiedTime: string;
      workspaceUris: string[];
    }>
  ) {
    const dbDir = path.join(homeDir, ".gemini", "antigravity-cli");
    fs.mkdirSync(dbDir, { recursive: true });
    const dbPath = path.join(dbDir, "conversation_summaries.db");
    const db = new Database(dbPath);
    db.run(
      "CREATE TABLE conversation_summaries (conversation_id text PRIMARY KEY, last_modified_time datetime NOT NULL, workspace_uris text NOT NULL)"
    );
    const stmt = db.prepare(
      "INSERT INTO conversation_summaries VALUES (?, ?, ?)"
    );
    for (const record of records) {
      stmt.run(
        record.conversationId,
        record.lastModifiedTime,
        JSON.stringify(record.workspaceUris)
      );
    }
    db.close();
  }

  function runAudit(): AuditRow[] {
    const result = spawnSync("bash", [auditScript, "-b", "main", repoDir], {
      cwd: repoDir,
      env: { ...process.env, HOME: homeDir },
      encoding: "utf-8",
    });
    expect(result.status).toBe(0);
    return parseAuditOutput(result.stdout);
  }

  it("recent agy chat moves clean workspace to verify-recent-chat", () => {
    const wt = createWorkspace("wt-recent");
    // Real agy rows carry nanoseconds: "2026-10-23 19:23:20.461873344+00:00".
    const nowIso = new Date()
      .toISOString()
      .replace("T", " ")
      .replace("Z", "873344+00:00");
    initAgyDb([
      {
        conversationId: "conv-recent",
        lastModifiedTime: nowIso,
        workspaceUris: [`file://${wt}`],
      },
    ]);

    const rows = runAudit();
    const row = rows.find((r) => r.worktree.includes("wt-recent"));
    expect(row).toBeDefined();
    expect(row?.bucket).toBe("verify-recent-chat");
    expect(row?.dirty).toBe("clean");
    expect(row?.merged).toBe("YES");
    expect(row?.lastChat).not.toBe("-");
    expect(row?.lastChat).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("stale agy chat marks merged workspace as safe", () => {
    const wt = createWorkspace("wt-stale");
    const staleDate = new Date(Date.now() - 10 * 86400000)
      .toISOString()
      .replace("T", " ")
      .replace("Z", "+00:00");
    initAgyDb([
      {
        conversationId: "conv-stale",
        lastModifiedTime: staleDate,
        workspaceUris: [`file://${wt}`],
      },
    ]);

    const rows = runAudit();
    const row = rows.find((r) => r.worktree.includes("wt-stale"));
    expect(row).toBeDefined();
    expect(row?.bucket).toBe("safe");
    expect(row?.dirty).toBe("clean");
    expect(row?.merged).toBe("YES");
    expect(row?.lastChat).not.toBe("-");
    expect(row?.lastChat).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("agy transcript that mentions the workspace path counts", () => {
    const wt = createWorkspace("wt-brain");
    createWorkspace("wt-brain-r37");
    // The chat started in the main repo, so its DB row points there.
    initAgyDb([
      {
        conversationId: "conv-main",
        lastModifiedTime: "2020-01-01 00:00:00+00:00",
        workspaceUris: [`file://${repoDir}`],
      },
    ]);
    const logs = path.join(
      homeDir,
      ".gemini/antigravity-cli/brain/conv-main/.system_generated/logs"
    );
    fs.mkdirSync(logs, { recursive: true });
    // agy escapes the quotes around tool arguments: {"Path":"\"/abs/path\""}
    fs.writeFileSync(
      path.join(logs, "transcript.jsonl"),
      JSON.stringify({ args: { Path: `"${wt}"` } }) + "\n"
    );

    const rows = runAudit();
    expect(rows.find((r) => r.worktree.endsWith("/wt-brain"))?.bucket).toBe(
      "verify-recent-chat"
    );
    expect(rows.find((r) => r.worktree.includes("wt-brain-r37"))?.bucket).toBe(
      "safe"
    );
  });

  it("DSH transcript that mentions the workspace path counts", () => {
    const wt = createWorkspace("wt-dsh");
    createWorkspace("wt-dsh-r37");
    const session = path.join(
      homeDir,
      ".dsh/sessions/--home-pi--/session-1"
    );
    fs.mkdirSync(session, { recursive: true });
    // DSH writes shell commands as "cd /abs/path && ...".
    const line = JSON.stringify({ command: `cd ${wt} && jj st` }) + "\n";
    fs.writeFileSync(
      path.join(session, "session.v4.jsonl.zstd"),
      Bun.zstdCompressSync(Buffer.from(line))
    );

    const rows = runAudit();
    expect(rows.find((r) => r.worktree.endsWith("/wt-dsh"))?.bucket).toBe(
      "verify-recent-chat"
    );
    expect(rows.find((r) => r.worktree.includes("wt-dsh-r37"))?.bucket).toBe(
      "safe"
    );
  });

  it("uncommitted changes mark workspace as hold-wip", () => {
    const wt = createWorkspace("wt-wip");
    fs.writeFileSync(path.join(wt, "draft.txt"), "work in progress");

    const rows = runAudit();
    const row = rows.find((r) => r.worktree.includes("wt-wip"));
    expect(row).toBeDefined();
    expect(row?.bucket).toBe("hold-wip");
    expect(row?.dirty).toMatch(/^wip:\d+/);
  });

  it("claude chat started in the workspace counts", () => {
    const wt = createWorkspace("wt-claude");
    const slug = wt.replace(/[/.]/g, "-");
    const claudeDir = path.join(homeDir, ".claude", "projects", slug);
    fs.mkdirSync(claudeDir, { recursive: true });
    fs.writeFileSync(path.join(claudeDir, "session.jsonl"), "{}\n");

    const rows = runAudit();
    const row = rows.find((r) => r.worktree.includes("wt-claude"));
    expect(row).toBeDefined();
    expect(row?.bucket).toBe("verify-recent-chat");
    expect(row?.dirty).toBe("clean");
    expect(row?.lastChat).not.toBe("-");
    expect(row?.lastChat).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
