# Vendored dependencies

All required dependency sources are ordinary repository files. No dependency
installation or downloads are needed during verification. Only selected files
were extracted from upstream release archives; no package metadata, Git history,
submodules, or external build scripts are required.

| Dependency | Release | Upstream archive | SHA-256 of downloaded archive |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.4.0 | https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.4.0 | `b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1` |
| Forge Standard Library | v1.9.7 | https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7 | `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94` |

OpenZeppelin files retained unchanged:

- `contracts/token/ERC20/ERC20.sol`
- `contracts/token/ERC20/IERC20.sol`
- `contracts/token/ERC20/extensions/IERC20Metadata.sol`
- `contracts/utils/Context.sol`
- `contracts/interfaces/draft-IERC6093.sol`
- `LICENSE` (MIT)

Forge Standard Library files retained unchanged: the entire `src/` directory,
`LICENSE-APACHE`, and `LICENSE-MIT` (Apache-2.0 OR MIT).
