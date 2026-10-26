# Implementation plan

- [x] 1. Add a bounded, allowlisted local snapshot reader; verify privacy and progress modes. (R1–3)
- [x] 2. Add shared validated models and a private CloudKit transport with pagination. (R2, R6)
- [x] 3. Add Mac opt-in settings, independent publisher, deletion/backoff and account handling. (R1–5, R8)
- [x] 4. Add read-only iPhone views, account-bound cache, stale labels and foreground refresh. (R5–7)
- [x] 5. Add Xcode schemes/capabilities and setup, privacy and usage documentation. (R8)
- [x] 6. Build, run regression/UI checks, test provisioned sync where available, and record remaining setup truthfully. Sync ordinary source files to the independent public repository. (R1–8)

## Automatic connection follow-up

- [x] 7. Default provisioned builds to automatic connected-project sync; preserve identity, exclusions, explicit stop and account boundaries during migration. (R1–5)
- [x] 8. Simplify Mac and iPhone instructions and disclose automatic summary sharing at connection time. (R1–2, R6)
- [x] 9. Verify automatic first upload, connection changes, exclusions, pause/restart, builds and installed daily app; sync ordinary source and documentation publicly. (R1–8)
