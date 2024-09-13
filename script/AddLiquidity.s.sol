// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDexRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract AddLiquidity is Script {
    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));

    // Set dex router for the network being deploying to
    address constant DEX_ROUTER_ADDRESS = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D //mainnet
    // 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 //sepolia

    // Load environment variables
    address constant UNAI_TOKEN_ADDRESS = address(0x0); // Enter UNAI token address
    uint256 constant ETH_AMOUNT = 2 ether; // Enter ETH amount
    uint256 constant TOKEN_AMOUNT = 1_000_000 ether; // Enter token amount

    IERC20 unaiToken;
    IDexRouter dexRouter;

    function setUp() public {
        // Initialize token and router contracts
        unaiToken = IERC20(UNAI_TOKEN_ADDRESS);
        dexRouter = IDexRouter(DEX_ROUTER_ADDRESS);
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Approve Uniswap router to spend UNAI tokens
        unaiToken.approve(DEX_ROUTER_ADDRESS, TOKEN_AMOUNT);
        console.log("Approved Uniswap router to spend UNAI tokens:", TOKEN_AMOUNT);

        // Add liquidity to Uniswap
        dexRouter.addLiquidityETH{value: ETH_AMOUNT}(
            address(unaiToken), // Token address
            TOKEN_AMOUNT, // Amount of tokens
            0, // Min tokens to add (slippage)
            0, // Min ETH to add (slippage)
            address(this), // Receiver of liquidity tokens
            block.timestamp + 300 // Deadline (300 seconds from now)
        );

        console.log("Liquidity added to Uniswap: %s tokens and %s ETH", TOKEN_AMOUNT, ETH_AMOUNT);

        vm.stopBroadcast();
    }
}
