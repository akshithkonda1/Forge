import { appendFile, mkdir } from "fs/promises";
import { NextResponse } from "next/server";

const LOG = "/opt/cursor/logs/debug.log";

export async function POST(req: Request) {
  try {
    const body = await req.json();
    await mkdir("/opt/cursor/logs", { recursive: true });
    await appendFile(LOG, JSON.stringify(body) + "\n");
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ ok: false, error: String(e) }, { status: 500 });
  }
}
