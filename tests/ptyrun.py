#!/usr/bin/env python3
"""ptyrun.py ANSWER CMD...: run CMD on a pseudo-terminal and type ANSWER at each "[y/N]" prompt.

Prints what the command wrote, then one line: [prompts=N rc=EXIT_CODE].
"""
import os
import pty
import select
import sys
import time

answer, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

buf = b""
prompts = 0
start = time.time()
while time.time() - start < 60:
    ready, _, _ = select.select([fd], [], [], 0.5)
    if fd not in ready:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    buf += data
    while buf.count(b"[y/N]") > prompts:
        os.write(fd, answer.encode() + b"\n")
        prompts += 1
else:
    os.kill(pid, 9)  # still running after 60 s: it waits for input that will not come

_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace").replace("\r\n", "\n"))
print(f"[prompts={prompts} rc={os.waitstatus_to_exitcode(status)}]")
