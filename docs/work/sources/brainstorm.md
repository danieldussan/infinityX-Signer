# Sources (repositorios de descargas de IPAs)

## Intent
"Podemos hacer que en nuestra app se agreguen repositorios de descargas como este?" (https://source.fouadraheb.com, fuente universal para Feather/ESign/GBox)

## Decisions
- (ninguna aún)

## Findings (verificado)
- La fuente es JSON estándar AltStore: `name`, `identifier`, `iconURL`, `apps[]`.
- Cada app: `name`, `bundleIdentifier`, `iconURL`, `subtitle`, `versions[]` (`version`, `date`, `downloadURL`, `size`, `localizedDescription`). También duplica `downloadURL`/`version` en la raíz de la app (formato v1 + v2).
- Esa fuente: 7 apps, 136 KB. IPAs pesan ~180 MB (Watusi).
- Una URL = un JSON. Agregar fuente = guardar URL + `GET` + decodificar.

## Options
Cómo entra la IPA descargada:
- **A (recomendada)**: descarga → `ImportStore` como IPA → aparece en el selector de Firmar. Reusa todo el pipeline de importación, progreso y selector ya hecho.
- B: descargar y firmar en un paso. Más cómodo, más acoplado; déjalo para después.

UI:
- **A (recomendada)**: sección nueva dentro de la pestaña Apps (o botón "Fuentes" en el tab IPA de Firmar). Lista de fuentes → lista de apps → botón Descargar.
- B: tab nuevo "Fuentes". Cinco tabs en la barra flotante: apretado.

Agregar fuente:
- Pegar URL en un campo. Extra opcional: deep link `infinityx://source?url=` (ya existe el esquema `infinityx://` para el token del certificado).

## Risks / unknowns
- IPAs de 180 MB: descarga debe ir con `URLSession` download task (a disco, con progreso, sin cargar en RAM). Segundo plano limitado por iOS.
- Espacio en disco: avisar tamaño antes de descargar (`size` viene en el JSON).
- Seguridad: la fuente decide qué IPA llega a la firma del usuario. Solo `https`; mostrar el dominio al agregar. No ejecutar nada, solo descargar.
- Algunas fuentes traen IPAs "sl" ya modificadas con tweaks; firmar IPAs ajenas es responsabilidad del usuario. Evitar fuentes preinstaladas.
- Formatos: algunas fuentes viejas usan solo v1 (sin `versions[]`). Decoder debe tolerar ambos.
- Posible conflicto de bundle id con la app original instalada (la fuente lo avisa en su descripción). Mostrar `localizedDescription`.

## Out of scope
- Catálogo propio/hospedado, buscador global, actualizaciones automáticas de apps, notificaciones de nuevas versiones, screenshots/permisos de privacidad.
- Instalar directo sin firmar.

## Refs
- https://source.fouadraheb.com (JSON de ejemplo)
- Formato AltStore source (v1/v2)
- Código tocado: `ImportStore.swift` (enqueue/IPA), `AppsView.swift`, `ContentView.swift`, `WebImport.swift` (deep link)

## Decisions (round 2)
- UI: tab "Certificado" -> "Importar" with segments Certificado | Fuentes (mockup `infinityx-signer/mockups/04-sources.html`). Apps keeps 3 segments.
- Fouad's Source seeded by default on first launch; removable; "Restaurar" row appears in Fuentes when absent.
- Downloaded IPA goes through `ImportStore.enqueue(.ipa)` (appears in Apps > Importadas / Firmar picker).
