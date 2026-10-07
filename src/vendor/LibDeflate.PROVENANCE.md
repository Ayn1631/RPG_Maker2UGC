# LibDeflate provenance

Upstream: https://github.com/SafeteeWoW/LibDeflate/tree/afc3b78d12fb3bcfa6b21e5332031ad3d7572e19

Version: 1.0.2-release. Original SHA256: 880e396fbaac7dcf99d33fc706a7f129147f2910f8414a143f8dea57e327c06b. License: zlib; see LibDeflate.LICENSE.txt and original source header.

Altered R2U version wraps the library in the module factory, disables optional LibStub integration, removes its standalone CLI, and adds maxOutput/maxWork arguments to DecompressZlib. Bounds are enforced before literal, match or stored-block output allocation and on bit/decode reads. The local string.byte wrapper converts bytes to doubles before upstream multi-byte arithmetic, preventing actual Fengari 32-bit integer overflow observed in native PNG tests. Compression and other APIs remain upstream code but are not part of the PNG product API. The changes must not be represented as unmodified upstream.
