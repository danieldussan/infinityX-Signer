# Plan: Fuentes (M)
1. `Sources/SourceStore.swift`: AltStore v1/v2 decoder, persisted list (sources.json), seed default, fetch, download to Application Support/Downloads -> `imports.enqueue`.
2. `Sources/SourcesView.swift`: list -> apps -> download; add sheet (verify then add).
3. `ImportTab` wrapper in ContentView: tab 0 renamed Importar, segments Certificado | Fuentes.
4. Unit tests for decoder in InfinityXCore? Decoder lives in App target -> only typecheck + decoder smoke test against real JSON.
5. `scripts/typecheck.sh`.
