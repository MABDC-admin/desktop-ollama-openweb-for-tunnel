import json
import sqlite3
import sys
import time


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: apply_default_blueprint.py <db_path> <prompt_path> <model_id>", file=sys.stderr)
        return 2

    db_path, prompt_path, model_id = sys.argv[1:]
    with open(prompt_path, "r", encoding="utf-8") as handle:
        blueprint = handle.read().strip()

    if not blueprint:
        raise RuntimeError("Blueprint prompt is empty.")

    now = int(time.time())

    conn = sqlite3.connect(db_path)
    try:
        admin = conn.execute(
            "select id from user where role = 'admin' order by created_at asc limit 1"
        ).fetchone()
        if not admin:
            raise RuntimeError("No admin user exists; cannot assign the workspace model owner.")

        user_id = admin[0]
        row = conn.execute(
            "select params, meta from model where id = ?",
            (model_id,),
        ).fetchone()

        if row:
            params = json.loads(row[0]) if row[0] else {}
            meta = json.loads(row[1]) if row[1] else {}
            params["system"] = blueprint
            meta.setdefault("description", "Default local Open WebUI blueprint prompt.")
            conn.execute(
                """
                update model
                   set params = ?,
                       meta = ?,
                       is_active = 1,
                       updated_at = ?
                 where id = ?
                """,
                (json.dumps(params, ensure_ascii=False), json.dumps(meta, ensure_ascii=False), now, model_id),
            )
        else:
            params = {"system": blueprint}
            meta = {
                "description": "Default local Open WebUI blueprint prompt.",
                "capabilities": {},
            }
            conn.execute(
                """
                insert into model (
                    id, user_id, base_model_id, name, params, meta, is_active, updated_at, created_at
                ) values (?, ?, ?, ?, ?, ?, 1, ?, ?)
                """,
                (
                    model_id,
                    user_id,
                    None,
                    model_id,
                    json.dumps(params, ensure_ascii=False),
                    json.dumps(meta, ensure_ascii=False),
                    now,
                    now,
                ),
            )

        conn.commit()
        conn.execute("pragma wal_checkpoint(full)")
    finally:
        conn.close()

    print(f"Applied default blueprint prompt to model {model_id}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
