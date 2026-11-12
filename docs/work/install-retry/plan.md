# install-retry (M)

Bug: "Reintentar" reinstalls every signed app; cancelled iOS prompts wait 120 s; closing the overlay leaves an
invisible queue; Apps tab shows spinners for queued apps.

1. Core: `QueueOutcome` + `queueSummary` (pure, tested).
2. Coordinator: items persist across runs (merge by ipaURL), `.cancelled` state, `cancelAll()`, `isRunning`,
   no-response timeout (45 s waiting for the iOS prompt), ignore late events for final items, `retryableApps`.
3. Batch overlay: retry only failed/cancelled, cancel button, honest toast/haptic.
4. Apps tab: per-row "Reintentar", global "Reintentar N", queued vs active spinner, cancel button, summary toast.
5. `InstallBanner` at the top while a queue runs (Cancelar) so closing the overlay never hides it.
Verify: `swift test` in Packages/InfinityXCore, `scripts/typecheck.sh`.
