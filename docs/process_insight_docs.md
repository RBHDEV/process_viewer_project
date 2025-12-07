# Process Viewer — OS Process Information Overview

## Purpose
- Show how an OS represents running processes (identifiers, resources, and state).
- Demonstrate practical ways to retrieve and interpret process information across platforms (Linux, macOS, Windows).
- Provide a small UI that maps OS concepts to human-readable information (PID, memory usage, CPU usage, state, owner/session) and simple controls (refresh, kill).

## How operating systems expose process information

- Linux/macOS (Unix-like):
  - The kernel maintains process control blocks (PCBs) that track metadata for each process: PID, PPID, UID/GID, program name, CPU and memory accounting, current state, open file descriptors, etc.
  - Many Unix-like OSes expose an interface under `/proc` (procfs) where each process has a directory such as `/proc/<pid>/` containing files with metrics: `stat`, `status`, `cmdline`, `fd/`, `maps`, and more.
  - User-space utilities like `ps`, `top`, and `htop` parse procfs or use system APIs to present process tables. `ps aux` prints commonly used columns (USER, PID, %CPU, %MEM, VSZ, RSS, STAT, START, COMMAND).

- Windows:
  - Windows also maintains kernel structures for processes and threads. The OS exposes process information via system APIs (e.g., PSAPI, WMI) and command-line tools such as `tasklist` and `taskkill`.
  - Output formats differ; `tasklist` reports memory in KB and includes image name, PID, session name, and memory usage.

## Key process fields and what they mean

- PID (Process Identifier): a unique integer assigned by the kernel to identify a process.
- PPID: the parent process ID (who spawned this process).
- USER / SESSION: owner account or session that runs the process.
- STATE / STAT: short code describing execution state (Running, Sleeping, Stopped, Zombie). Codes differ by OS (`R`, `S`, `D`, `T`, `Z` on Linux; textual states in other tools).
- CPU%: instantaneous or averaged CPU usage percent for the process (calculated from times and elapsed wall clock).
- Memory: reported as RSS (resident set size) and/or VSZ (virtual size). Tools may show different units (KB, MB).
- COMMAND / IMAGE: the command or executable name that created the process.

## How the app extracts/processes this information

- Linux/macOS: the app runs `ps aux` (or `ps aux --no-headers`) and parses the whitespace-separated columns to obtain USER, PID, %CPU, %MEM (or memory columns), STAT, and the command. This mirrors how many monitoring tools operate when not using procfs directly.
- Windows: the app runs `tasklist /FO CSV /NH` and parses the CSV output to extract Image Name, PID, Session Name, and Memory Usage (KB).
- The app normalizes values for display (e.g., converting memory into MB/GB for readability, mapping short state codes to human-readable state names).
- The app demonstrates process control by invoking `kill` (Unix) or `taskkill` (Windows) to terminate a process — this highlights kernel-enforced permission checks: the operation succeeds only if the user has sufficient privileges.

## What this demonstrates about OS internals (learning points)

- Processes are kernel-managed entities with identifiers and accounting metadata.
- The OS provides interfaces (procfs, system APIs, command-line utilities) for user-space to inspect running processes.
- Resource reporting is approximate and depends on sampling and timing (CPU% is derived from time deltas; memory reported may be RSS or virtual memory).
- State values (R/S/D/T/Z) represent scheduling, blocking, IO-wait, or termination conditions.
- Terminating processes is mediated by the kernel and subject to permissions (UID, ACLs, or elevated privileges on Windows).

## Limitations and caveats

- Parsing `ps` or `tasklist` output is simple and portable but brittle — format changes or localized output can break parsers. Using native APIs or reading `/proc/<pid>/` directly is more robust on Unix-like systems.
- CPU and memory metrics are sampled values, not precise instantaneous measures.
- Some process information is restricted for security reasons (e.g., processes owned by other users may hide command lines or details unless privileged).
- Killing processes forcibly (`kill -9`) bypasses graceful shutdown, which can lead to resource leaks; use judiciously.

## Suggested extensions (for deeper OS coursework)

- Read `/proc/<pid>/stat` and `/proc/<pid>/status` directly on Linux to demonstrate parsing kernel-provided files.
- Show per-thread information and thread states.
- Visualize process trees (PPID relationships) to illustrate parent/child behavior and orphaned processes.
- Add permission-aware features: escalate via `sudo` on Linux or require Administrator rights on Windows and demonstrate the effect.
- Use sampling over time to graph CPU and memory trends per process.

## How to run the app (quick)

1. Ensure you have Flutter and a supported desktop target installed (Linux/macOS/Windows).
2. From the project root run:

```bash
flutter analyze
flutter run -d linux   # or -d macos / -d windows as appropriate
```

3. Use the UI to refresh process data, search, filter by state, and (with appropriate permissions) kill a process to observe how the OS enforces access.

---