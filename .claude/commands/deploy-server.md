---
description: Build the online server, deploy it to gutshof-guentert.de and restart it there
---

Deploy the online server with the fixed script and report. Reply in German.

1. Run `powershell -ExecutionPolicy Bypass -File tools/deploy-server.ps1`
   (tests, protocol check, Linux build, copy, install, restart, check).
   Do not run its steps by hand and do not work around a failure.
2. If it stops at the protocol check (the released game would no longer get
   online): tell the user and ask (AskUserQuestion) whether to deploy anyway.
   Only on a yes run it again with `-Force`.
3. Any other failure: show the script's output and stop. If the service does
   not run after the restart, offer the rollback the script prints (do not
   run it unasked).
4. Success: report the build size, the tests, whether the systemd unit
   changed, and the service / port / journal lines the script printed. Say
   that the restart dropped races that were running.
