# Build inputs

Ferry builds offline from a cache folder (`$FERRY_CACHE`, default `~/Developer/ferry-cache`).
Put these files in it; the build checks them against these sha256 sums.

| File | Bytes | sha256 |
|---|---|---|
| `crossover-sources-26.3.0.tar.gz` | 149054023 | `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872` |
| `dxmt-v0.80-builtin.tar.gz` | 18681669 | `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` |
| `proton-164e0ccd.tar.gz` | 121316710 | `136aa6600501e279dba0b1efaee9f81e837d043a296f4286e1d3f966ca1e007a` |
| `dobby-5dfc8546.tar.gz` | 154712 | `7220cb466788db34f68e2209fa9dc86135aa52109b641d7b207bbd55d79a69ac` |
| `notproton-e054db0.tar.gz` | 90889428 | `16c85e621032d5ec6d0df24d9c04d97b57912ef9fb3ae843d0a0194822a5b9f7` |
| `SDL2-2.32.10.tar.gz` | 7630262 | `5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165` |
| `MoltenVK-1.4.2-macos.tar` | 59563008 | `f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e` |
| `nettle-3.10.tar.gz` | 2640485 | `b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c` |

Folders the upstream NotProton scripts set up and verify themselves:
`proton-lsc/`, `lsteamclient-tree/`, `steam-shim-headers/`, `steam-shim-headers-out/`, `valve-packages/`, `swiftpm/`.

Also needed:
- `wine-11.15/`: a git checkout of https://gitlab.winehq.org/wine/wine at tag `wine-11.15`
  (commit `2df1ee28039cf84776eb1421ed90bd154cebb65f`), used to build the bridge.
- `gptk/redist/`: your own download of Apple's Game Porting Toolkit (tested with 4.0 beta 2),
  from developer.apple.com. Apple's licence forbids redistribution, so it is never committed.
- `fontvenv/`: a Python venv with `afdko<5` (5.0 broke `makeotfexe`, used by Proton's font build) and `fonttools`.

Sources: CrossOver sources from codeweavers.com/crossover/source, DXMT from github.com/3Shain/dxmt,
Proton from github.com/ValveSoftware/Proton, NotProton from github.com/NotProtonNot/NotProton (commit `e054db0`),
Dobby from github.com/jmpews/Dobby, SDL2, MoltenVK (Khronos release), Nettle/GMP/GnuTLS from their upstream releases.
