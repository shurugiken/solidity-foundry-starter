# solidity-foundry-starter

A Foundry project demonstrating Solidity development fundamentals: an ERC-20 token and a simple escrow contract, both with comprehensive forge-std tests.

> **Note:** This is a fundamentals/learning project intended to demonstrate Solidity and testing patterns. It is not a production-deployed service.

## What This Demonstrates

- Clean ERC-20 implementation (from scratch, Solidity ^0.8.20)
- Multi-party escrow pattern with `deposit`, `release`, and `refund` flows
- Foundry / forge-std testing: unit tests, revert assertions, event assertions, access control
- Standard Foundry project layout (`src/`, `test/`, `foundry.toml`)

## Contracts

| Contract | Description |
|---|---|
| `src/Token.sol` | Minimal ERC-20 with `mint`, `transfer`, `approve`, and `transferFrom` |
| `src/Escrow.sol` | Buyer/seller/arbiter escrow with deposit, release, and refund logic |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

```bash
# Install Foundry (curl-based installer)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify:

```bash
forge --version
```

## Setup

```bash
git clone https://github.com/shurugiken/solidity-foundry-starter.git
cd solidity-foundry-starter

# Install forge-std (the Foundry testing library)
forge install foundry-rs/forge-std --no-commit
```

`forge-std` is the only dependency. It is not bundled with the Foundry toolchain; the command above fetches it into `lib/forge-std/` where the compiler expects it.

## Running Tests

```bash
# Run all tests
forge test

# Run with verbose output (shows test names and logs)
forge test -v

# Run with gas reports
forge test --gas-report

# Run a specific test file
forge test --match-path test/Token.t.sol -v
forge test --match-path test/Escrow.t.sol -v
```

## Project Structure

```
solidity-foundry-starter/
├── foundry.toml          # Foundry configuration
├── src/
│   ├── Token.sol         # ERC-20 token
│   └── Escrow.sol        # Buyer/seller/arbiter escrow
└── test/
    ├── Token.t.sol       # Token unit tests
    └── Escrow.t.sol      # Escrow unit tests
```

## License

MIT — see [LICENSE](LICENSE)
