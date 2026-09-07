# soteria viewer + launcher

Live log monitor + visual session wizard. Stdlib only, bundled into the onefile binary.

```bash
./soteria launch --ui        # wizard + monitor at http://127.0.0.1:PORT/
python3 ui/server.py --port 8787                      # standalone server
SOTERIA_LOG=~/.soteria/records.ndjson python3 ui/server.py   # live log
```

Filter by level, search text, pause/clear; each row expands to raw JSON.
