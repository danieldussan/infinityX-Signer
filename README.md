# Infinity X Signer

App iOS (SwiftUI) para firmar e instalar IPAs en lote directamente desde el iPhone. Tú traes tu propio IPA, certificado (.p12) y perfil (.mobileprovision); la app no incluye ninguno. No se hace ninguna promesa sobre el estado legal del uso que le des: es responsabilidad tuya.

## Compilar (GitHub Actions)

No hace falta Xcode local. El workflow `.github/workflows/build.yml` corre en un runner macOS:

1. Hace push a `main` (o lanza el workflow a mano desde la pestaña Actions).
2. El job ejecuta los tests de `Packages/InfinityXCore`, genera el proyecto con XcodeGen (`project.yml`) y compila sin firmar.
3. Descarga `InfinityXSigner-<versión>.ipa` desde los artefactos del run. Con un tag `v*` (que debe coincidir con `MARKETING_VERSION` de `project.yml`) se publica como `InfinityXSigner-vX.Y.Z.ipa` en un GitHub Release.

El IPA resultante no está firmado: instálalo con tu herramienta de sideload habitual.

## Uso

1. Pestaña **Certificados**: importa tu `.p12` y tu `.mobileprovision`, selecciónalos y guarda la contraseña (queda en el Keychain).
2. Pestaña **IPAs**: importa el IPA a firmar y selecciónalo.
3. Pestaña **Firmar**: define prefijo de nombre, prefijo de bundle id y un rango (`21-25`, `21,23`) o una cantidad "siguientes N". Pulsa Firmar.
4. Los IPAs firmados quedan en `Documents/Signed/` y se pueden exportar con la hoja de compartir.
5. Pestaña **Ajustes**: modo de instalación (Semi Local por defecto, Fully Local experimental, Solo exportar), host del plist, paquete SSL y registro de errores.

El perfil debe cubrir el bundle id generado (por ejemplo un perfil comodín).
