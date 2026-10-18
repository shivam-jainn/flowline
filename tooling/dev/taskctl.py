#!/usr/bin/env python3
"""
⚡️ taskctl — Lightweight Terminal Task & Sprint CLI App
Used for terminal workflow automation, fast-forward typing tests, and CLI capture in Flowline.
"""

import sys
import json
import argparse
import os
import time

TASKS_FILE = os.path.expanduser("~/.flowline_tasks.json")

DEFAULT_TASKS = [
    {"id": "TASK-101", "title": "Configure WebKit offscreen renderer for Playground", "status": "done", "priority": "high", "tag": "core"},
    {"id": "TASK-102", "title": "Implement live DOM coordinate resolution in WKWebView", "status": "done", "priority": "high", "tag": "capture"},
    {"id": "TASK-103", "title": "Run automated multi-page 10-step verification suite", "status": "open", "priority": "high", "tag": "testing"},
    {"id": "TASK-104", "title": "Synthesize CLI execution guide with 1-click copyable blobs", "status": "open", "priority": "medium", "tag": "cli"},
    {"id": "TASK-105", "title": "Publish dark theme HTML documentation bundle", "status": "open", "priority": "low", "tag": "publishing"}
]

def load_tasks():
    if os.path.exists(TASKS_FILE):
        try:
            with open(TASKS_FILE, "r") as f:
                return json.load(f)
        except Exception:
            return DEFAULT_TASKS
    return list(DEFAULT_TASKS)

def save_tasks(tasks):
    try:
        with open(TASKS_FILE, "w") as f:
            json.dump(tasks, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not persist tasks ({e})", file=sys.stderr)

def cmd_list(args):
    tasks = load_tasks()
    if args.status:
        tasks = [t for t in tasks if t.get("status") == args.status]
    if args.tag:
        tasks = [t for t in tasks if t.get("tag") == args.tag]
        
    if args.json:
        print(json.dumps(tasks, indent=2))
        return

    print("⚡️ [taskctl] Sprint Backlog & Execution Queue")
    print("═" * 70)
    print(f"{'ID':<10} {'STATUS':<10} {'PRIORITY':<10} {'TAG':<10} {'TITLE'}")
    print("─" * 70)
    for t in tasks:
        status_symbol = "✓ DONE" if t["status"] == "done" else "○ OPEN"
        priority_badge = f"[{t['priority'].upper()}]"
        print(f"{t['id']:<10} {status_symbol:<10} {priority_badge:<10} {t.get('tag', 'dev'):<10} {t['title']}")
    print("═" * 70)
    done_count = sum(1 for t in tasks if t["status"] == "done")
    print(f"Total: {len(tasks)} tasks | Completed: {done_count} | Open: {len(tasks) - done_count}")

def cmd_add(args):
    tasks = load_tasks()
    next_num = 101 + len(tasks)
    new_task = {
        "id": f"TASK-{next_num}",
        "title": args.title,
        "status": "open",
        "priority": args.priority,
        "tag": args.tag
    }
    tasks.append(new_task)
    save_tasks(tasks)
    print(f"✓ Added task: {new_task['id']} — \"{new_task['title']}\" [{new_task['priority']}]")

def cmd_complete(args):
    tasks = load_tasks()
    found = False
    for t in tasks:
        if t["id"].upper() == args.id.upper():
            t["status"] = "done"
            found = True
            print(f"✓ Task completed: {t['id']} — \"{t['title']}\"")
            break
    if not found:
        print(f"❌ Error: Task '{args.id}' not found.", file=sys.stderr)
        sys.exit(1)
    save_tasks(tasks)

def cmd_stats(args):
    tasks = load_tasks()
    total = len(tasks)
    done = sum(1 for t in tasks if t["status"] == "done")
    open_count = total - done
    pct = (done / total * 100.0) if total > 0 else 0.0
    
    if args.json:
        print(json.dumps({
            "total": total,
            "done": done,
            "open": open_count,
            "completion_rate": f"{pct:.1f}%"
        }, indent=2))
        return

    print("📊 [taskctl] Sprint Progress Metrics")
    print("─" * 40)
    print(f"  Total Tasks:       {total}")
    print(f"  Completed:         {done}")
    print(f"  Open:              {open_count}")
    print(f"  Completion Rate:   {pct:.1f}%")
    bar_len = int(pct / 5)
    bar = "█" * bar_len + "░" * (20 - bar_len)
    print(f"  Progress:          [{bar}] {pct:.1f}%\n")

def cmd_batch(args):
    print("⚡️ [taskctl] Dispatching simulated batch operations...")
    stages = [
        "Resolving project dependency lockfiles",
        "Compiling Swift source targets (Flowline app, Swift modules)",
        "Spawning offscreen WebKit render context",
        "Executing headless playground page inspection",
        "Emitting unified markdown and static HTML report"
    ]
    for i, stage in enumerate(stages, 1):
        print(f"  [{i}/{len(stages)}] {stage}...")
        time.sleep(0.05)
    print("✓ All batch operations succeeded.")

def main():
    parser = argparse.ArgumentParser(
        prog="taskctl",
        description="⚡️ taskctl — Terminal Task & Sprint CLI for Flowline workflows"
    )
    subparsers = parser.add_subparsers(dest="command")

    # list
    p_list = subparsers.add_parser("list", help="List tasks in the queue")
    p_list.add_argument("--json", action="store_true", help="Output in JSON format")
    p_list.add_argument("--status", choices=["open", "done"], help="Filter by status")
    p_list.add_argument("--tag", help="Filter by tag")

    # add
    p_add = subparsers.add_parser("add", help="Add a new task")
    p_add.add_argument("title", help="Task summary title")
    p_add.add_argument("--priority", choices=["low", "medium", "high"], default="medium", help="Priority level")
    p_add.add_argument("--tag", default="dev", help="Tag category (e.g. core, capture, ui)")

    # complete
    p_complete = subparsers.add_parser("complete", help="Mark a task as done")
    p_complete.add_argument("id", help="Task ID (e.g. TASK-103)")

    # stats
    p_stats = subparsers.add_parser("stats", help="Show sprint statistics")
    p_stats.add_argument("--json", action="store_true", help="Output in JSON format")

    # batch
    subparsers.add_parser("run-batch", help="Run simulated batch developer workflow")

    args = parser.parse_args()

    if args.command == "list":
        cmd_list(args)
    elif args.command == "add":
        cmd_add(args)
    elif args.command == "complete":
        cmd_complete(args)
    elif args.command == "stats":
        cmd_stats(args)
    elif args.command == "run-batch":
        cmd_batch(args)
    else:
        cmd_list(argparse.Namespace(status=None, tag=None, json=False))

if __name__ == "__main__":
    main()
