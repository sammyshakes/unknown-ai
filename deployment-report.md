# Testnet Deployment Report

## Key Contracts

| Contract  | Address                                    | Etherscan Link                                                                          |
| --------- | ------------------------------------------ | --------------------------------------------------------------------------------------- |
| UNAI V1   | 0x96666d6bdD2CC52ef5f6A379D13f8F59866b9F90 | [View](https://sepolia.etherscan.io/address/0x96666d6bdD2CC52ef5f6A379D13f8F59866b9F90) |
| UNAI V2   | 0x27b42d3096B4358bE7cEcF332F2F1bD4e19F0128 | [View](https://sepolia.etherscan.io/address/0x27b42d3096B4358bE7cEcF332F2F1bD4e19F0128) |
| Migration | 0xD07be3B9FECcca041e89B29763cabF2C292400a8 | [View](https://sepolia.etherscan.io/address/0xD07be3B9FECcca041e89B29763cabF2C292400a8) |

## Deployment Details

**Network**: Sepolia Testnet (Chain ID 11155111)  
**Deployer**: 0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023

### Gas Costs

| Contract  | Gas Used  | ETH Cost (Sepolia) |
| --------- | --------- | ------------------ |
| UNAI V1   | 3,620,103 | 0.00399 ETH        |
| UNAI V2   | 3,620,476 | 0.00432 ETH        |
| Migration | 670,728   | 0.00078 ETH        |

## Verification Commands

```bash
# V1 Verification
forge verify-contract 0x96666d6bdD2CC52ef5f6A379D13f8F59866b9F90 \\
  test/UNAIV1Mock.sol:Contract \\
  --constructor-args $(cast abi-encode "constructor(address,address)" \\
  0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023 \\
  0xc532a74256D3Db42D0Bf7a0400fEFDbad7694008) \\
  --compiler-version 0.8.24 --chain 11155111

# V2 Verification
forge verify-contract 0x27b42d3096B4358bE7cEcF332F2F1bD4e19F0128 \\
  src/UNAI.sol:Contract \\
  --constructor-args $(cast abi-encode "constructor(address,address)" \\
  0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023 \\
  0xc532a74256D3Db42D0Bf7a0400fEFDbad7694008) \\
  --compiler-version 0.8.24 --chain 11155111
```

## Key Transactions

- Transferred 100,000,000 V2 tokens to Migration contract
- Created Uniswap V2 pairs for both token versions
- All contracts verified on Etherscan
