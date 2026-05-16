### Empty audit output from router

During testing the `router_audit_wrapper.sh` script, the remote command `logread -e` returned **no data**, causing the wrapper to exit with:
```
[router_audit] No log retrieved from router.
```

#### Likely causes
- **Logging disabled** in the router UI.  In AsusWRT‑Merlin go to **Administration → System → System Log** and ensure "Enable syslog" is checked.
- **Log buffer empty** because the router has just booted or hasn't recorded any events yet.
- The router is configured to write logs to a file (e.g. `/jffs/logs/syslog.log`) rather than the in‑memory buffer.

#### Work‑arounds / fixes
1. **Enable syslog** on the router and wait a few minutes for entries to appear.
2. Switch the remote command to read a persistent log file if one exists:
   ```bash
   REMOTE_LOG_CMD="cat /jffs/logs/syslog.log"
   ```
3. Use the built‑in `hermes-audit.sh full_audit` command, which aggregates multiple sections and may produce output even when `logread` is empty.
4. Add a fallback in the wrapper script to run `hermes-audit.sh full_audit` when `logread` yields nothing.

After enabling logging, re‑run the cron job (`hermes cron run <job_id>`) and you should receive a full audit summary.
