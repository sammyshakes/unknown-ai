# UNAI Token and Staking Marketplace

This project implements a custom ERC20 token (UNAI), a staking vault, and a marketplace for trading staked positions. It includes smart contracts written in Solidity and tests using the Forge testing framework.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Running Tests](#running-tests)
- [Contracts Overview](#contracts-overview)
- [Contributing](#contributing)
- [License](#license)


## Installation

1. Clone the repository:
   ```
   git clone git@github.com:sammyshakes/unknown-ai.git
   cd unknown-ai
   ```

2. Install dependencies:
   ```
   forge install
   ```

## Configuration

1. Create a `.env` file in the root directory of the project.

2. Add your RPC URL to the `.env` file. Here's an example of what your `.env` file should look like:

   ```
   SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/your-api-key
   ETHERSCAN_API_KEY=your_etherscan_api_key_here
   ```

   Replace `your-api-key` with your actual API key from a provider like Alchemy or Infura.
   

3. Load the environment variables:
   ```
   source .env
   ```

## Project Structure

The project is structured as follows:

```
unknown-ai/
├── src/
│   ├── UNAI.sol
│   ├── UNAIStaking.sol
│   └── UNAIStakeMarketplace.sol
├── test/
│   └── StakeMarketplaceTest.t.sol
├── lib/
├── script/
├── .env
└── README.md
```

- `src/`: Contains the main smart contracts.
- `test/`: Contains the test files.
- `lib/`: Contains external libraries (managed by Forge).
- `script/`: Contains deployment and interaction scripts.
- `.env`: Contains environment variables (not tracked by git).

## Running Tests

To run the tests, use the following command in the project root directory:

```
forge test -vv --fork-url sepolia
```


To run a specific test file or function, you can use:

```
forge test --match-path test/StakeMarketplaceTest.t.sol -vv --fork-url $RPC_URL
forge test --match-test testCreateListing -vv --fork-url $RPC_URL
```

## Contracts Overview

1. **UNAI.sol**: Implements the UNAI ERC20 token with additional features like staking rewards.

2. **UNAIStaking.sol**: Implements the staking vault where users can stake their UNAI tokens.

3. **UNAIStakeMarketplace.sol**: Implements a marketplace for trading staked positions.
