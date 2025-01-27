# UNAI Token

This project implements a custom ERC20 token (UNAI) with built-in fee collection and distribution mechanisms, along with a migration contract for upgrading to future versions. It includes smart contracts written in Solidity and tests using the Forge testing framework.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Running Tests](#running-tests)
- [Contracts Overview](#contracts-overview)

## Installation

1. Clone the repository:

   ```bash
   git clone git@github.com:sammyshakes/unknown-ai.git
   cd unknown-ai
   ```

2. Install dependencies:

   ```bash
   forge install
   ```

## Configuration

1. Create a `.env` file in the root directory of the project.

2. Add your RPC URL to the `.env` file. Here's an example of what your `.env` file should look like:

   ```bash
   SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/your-api-key
   ETHERSCAN_API_KEY=your_etherscan_api_key_here
   ```

   Replace `your-api-key` with your actual API key from a provider like Alchemy or Infura.

3. Load the environment variables:

   ```bash
   source .env
   ```

## Project Structure

The project is structured as follows:

```bash
unknown-ai/
├── src/
│   ├── UNAI.sol
│   └── UNAIMigration.sol
├── test/
│   ├── UNAITest.t.sol
│   └── UNAIMigration.t.sol
├── script/
│   ├── Deploy.s.sol
│   ├── DeployUNAI.s.sol
│   ├── DeployV2Migration.s.sol
│   └── AddLiquidity.s.sol
├── lib/
├── .env
└── README.md
```

- `src/`: Contains the main smart contracts
- `test/`: Contains the test files
- `script/`: Contains deployment and interaction scripts
- `lib/`: Contains external libraries (managed by Forge)
- `.env`: Contains environment variables (not tracked by git)

## Running Tests

To run all tests:

```bash
forge test -vvv --rpc-url sepolia
```

To run specific test files:

```bash
# Run UNAI token tests
forge test --match-path test/UNAITest.t.sol -vvv --rpc-url sepolia

# Run migration tests
forge test --match-path test/UNAIMigration.t.sol -vvv --rpc-url sepolia
```

## Contracts Overview

### UNAI.sol

The main ERC20 token contract with the following features:

- Buy and sell fees (configurable)
- Automatic fee collection and distribution
- Operations and development fund allocation
- Automatic liquidity management
- Owner-controlled fee parameters
- Protection against excessive fees

### UNAIMigration.sol

Handles the migration from V1 to V2 tokens:

- Secure token migration mechanism
- 1:1 exchange rate
- Owner-controlled withdrawals
- Reentrancy protection
- Balance tracking for both V1 and V2 tokens

## Scripts

- `Deploy.s.sol`: General deployment script
- `DeployUNAI.s.sol`: Deploys the UNAI token contract
- `DeployV2Migration.s.sol`: Deploys the migration contract
- `AddLiquidity.s.sol`: Adds initial liquidity to the DEX pair

## Security Features

- Reentrancy protection on critical functions
- Owner access control for sensitive operations
- Fee limits to prevent excessive taxation
- Safe math operations via Solidity 0.8.x
- Comprehensive test coverage

## Testing

```bash
forge test --rpc-url sepolia

[⠊] Compiling...
[⠊] Compiling 4 files with Solc 0.8.24
[⠒] Solc 0.8.24 finished in 17.02s
Compiler run successful!

Ran 12 tests for test/UNAITest.t.sol:UNAITest
[PASS] testAddressUpdates() (gas: 29019)
[PASS] testBuyFees() (gas: 147347)
[PASS] testConstructorZeroAddressValidation() (gas: 523968)
[PASS] testContractExcludedFromFees() (gas: 188973)
[PASS] testFeeDistribution() (gas: 416978)
[PASS] testFeeUpdates() (gas: 46271)
[PASS] testOnlyOwnerCanUpdateFees() (gas: 17585)
[PASS] testPreventInvalidFeeUpdates() (gas: 47370)
[PASS] testSellFees() (gas: 328716)
[PASS] testSwapEnabled() (gas: 251916)
[PASS] testSwapThreshold() (gas: 21027)
[PASS] testTransfer() (gas: 49102)
Suite result: ok. 12 passed; 0 failed; 0 skipped; finished in 4.77s (1.96s CPU time)

Ran 10 tests for test/UNAIMigration.t.sol:UNAIMigrationTest
[PASS] testConstructorValidation() (gas: 246082)
[PASS] testGetBalances() (gas: 111384)
[PASS] testMigrateTokens() (gas: 114182)
[PASS] testReentrancyProtection() (gas: 887187)
[PASS] testWithdrawV1Tokens() (gas: 115122)
[PASS] testWithdrawV2Tokens() (gas: 43515)
[PASS] test_RevertWhen_MigratingWithInsufficientV2Balance() (gas: 52106)
[PASS] test_RevertWhen_MigratingWithoutApproval() (gas: 28640)
[PASS] test_RevertWhen_NonOwnerWithdrawsV1Tokens() (gas: 14001)
[PASS] test_RevertWhen_NonOwnerWithdrawsV2Tokens() (gas: 14289)
Suite result: ok. 10 passed; 0 failed; 0 skipped; finished in 5.06s (1.48s CPU time)

Ran 2 test suites in 5.84s (9.83s CPU time): 22 tests passed, 0 failed, 0 skipped (22 total tests)
```
