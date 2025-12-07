# Process Viewer — Brief Summary

Objective
- Create a program that lists currently running processes and displays a table with: Process Name, PID, Session Name (if available), Memory Usage, and Current State.

How this project meets the objective
- Cross-platform methods: Linux/macOS use `ps` or `/proc`, Windows uses `tasklist` or system APIs.
- This repo provides:
  - A Flutter desktop UI that runs platform commands and parses results for the interactive viewer.
  - A small Python CLI `scripts/list_processes.py` (uses `psutil`) that prints the required table.

Run (examples)
```bash
# Flutter UI (desktop)
flutter run -d linux

# Python CLI
pip install psutil
python3 scripts/list_processes.py
```

Notes
- Parsing command output is simple but brittle; using native APIs or `/proc` is more robust.
- Some process details may be restricted by permissions.


Made By RBHDEV (Ramzi Bouhadjar)
--------------------------------

