
# Quiet task

A measurement or other timing-sensitive operation runs on this host while you
work. Do not run tests, builds, benchmarks, type checkers, linters or any
other CPU- or I/O-heavy command. Write and re-read the code and tests, then
report. Under GATES, write "not run: quiet task (the planner runs them after
the measurement)". Expect a follow-up round in which the planner's focused
checks run and their failures come back as feedback.
