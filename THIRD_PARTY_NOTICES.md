# Third-party components

The installable release ZIP contains third-party runtime components required by this patch.

## BepInEx

- Project: BepInEx/BepInEx
- Runtime version used by this project: 5.4.23.5
- License: GNU Lesser General Public License v2.1 (LGPL-2.1)
- Upstream: https://github.com/BepInEx/BepInEx
- License text: `third_party/BepInEx-LICENSE.txt`

The distributed BepInEx runtime has compatibility adjustments for this RO3 client. The historical patching scripts used to produce/debug those adjustments are kept under `tools/legacy-runtime-patching/`.

`third_party/reference/BepInEx.dll` is an unmodified build-time reference used to compile `RO3.LocalizationTablePatcher.dll`; it is covered by the same BepInEx license above.

## XUnity AutoTranslator / XUnity ResourceRedirector

- Project: bbepis/XUnity.AutoTranslator
- AutoTranslator version: 5.6.2
- ResourceRedirector version: 2.1.0
- License: MIT
- Upstream: https://github.com/bbepis/XUnity.AutoTranslator
- License text: `third_party/XUnity-AutoTranslator-LICENSE.txt`

`XUnity.ResourceRedirector` is built and released from the XUnity.AutoTranslator repository.

## TextMeshPro fallback font asset

`Client/arialuni_sdf_u2022` is the prebuilt TextMeshPro fallback asset used by XUnity AutoTranslator. It was taken from XUnity AutoTranslator's official `TMP_Font_AssetBundles_2025-05-12.7z` release asset (v5.4.5). The repository copy was hash-checked against the locally preserved upstream archive before publication.

- SHA-256: `DE18A759D475E01F90CFFEE16BDC861BF3AA09BC501F3C622E5822622B5E1606`
- Upstream releases: https://github.com/bbepis/XUnity.AutoTranslator/releases

Third-party names and trademarks belong to their respective owners.
