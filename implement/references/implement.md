# Implementation discipline

Test-first, in vertical slices. Self-contained — no external skill needed. Read by the implementation subagent: `spec.md` is your contract, this file is how you execute it. Your work is validated against the spec by the orchestrator — unverifiable claims won't pass.

## The loop

For each acceptance criterion in `spec.md`, repeat:

1. **RED** — write ONE test for the next thinnest slice of behavior. Run it; watch it fail for the expected reason (a test that passes immediately is testing nothing, or the behavior already exists — check which).
2. **GREEN** — write the minimum implementation that makes it pass. Run the test.
3. **REFACTOR** — clean up what the last slice made ugly (duplication, naming, structure) while everything stays green. Then commit the slice.

Never batch: writing all tests first and all implementation after ("horizontal slicing") produces tests that encode imagined behavior and the shape of data structures instead of real behavior. One test → one implementation → repeat; each test responds to what the previous cycle taught.

## What a good test looks like

- Exercises behavior through a **public interface** (API endpoint, exported function, UI action) — not private methods or internal collaborators.
- Reads like a line of the spec: "expired token returns 401", not "calls validate() twice".
- Survives refactors. If renaming an internal function breaks a test, the test was testing implementation, not behavior — fix the test.
- Asserts through the same interface it acts through (don't write via the API then assert by querying the database directly, unless the DB row IS the contract).

## Mocking

Mock only true boundaries: external services, clocks, randomness, the network. Never mock the code under test or its in-process collaborators — if a test needs that, the test is at the wrong level or the code needs a seam. Prefer the project's existing test fixtures/factories over new mocks; match the conventions already in its test suite.

## Fitting the repo

- Follow the existing test layout, runner, naming, and assertion style — discover them from neighboring tests before writing the first one.
- Run the **project's** test command (`commands.test` from project.json), not an improvised one; a subset filter while iterating is fine, but the full suite must pass before verification.
- Commit per slice with the repo's existing message conventions; each commit should leave the suite green. NO `Co-Authored-By` trailers, "Generated with" lines, or any other AI attribution.
