---
name: debug-failing-test
description: Diagnose and fix a reproducible failing automated test by isolating the failure, tracing it to the smallest responsible code path, and verifying the correction. Use when the user provides a failing test, test output, or asks to fix a test-suite regression.
---

# Debug a failing test

1. Reproduce the failure with the narrowest available test command. Record the command and the meaningful error output.
2. Read the failing test's setup and assertion, then inspect the closest production code on that path. Avoid scanning unrelated parts of the repository until the evidence points there.
3. Decide whether the failure exposes a product defect, an outdated test, or an environment problem. State the working hypothesis before changing code.
4. Make the smallest correction consistent with the intended behavior. Do not weaken an assertion, delete coverage, or add retries merely to make the test pass unless the requirements justify that change.
5. Rerun the exact failing test. If it passes, run the nearest relevant suite when its cost is reasonable.
6. Report the root cause, changed files, verification commands and results, and any relevant validation that was not run.

If the failure cannot be reproduced, compare the reported environment, dependencies, platform, and invocation with the local run. Do not make a speculative code change without evidence.

For an intermittent failure, repeat the narrow test and investigate shared state, ordering, timing, and concurrency before treating retries as a fix.
