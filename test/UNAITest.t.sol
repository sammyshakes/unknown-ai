// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Contract} from "../src/UNAI.sol";
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

contract UNAITest is Test {
    Contract public unaiToken;
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);

    // Setup users
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    address public operationsAddress = address(0x3);
    address public devAddress = address(0x4);

    function setUp() public {
        // Deploy the UNAI token contract
        unaiToken = new Contract(operationsAddress, devAddress);

        // Provide liquidity to the pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount);

        unaiToken.approve(address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{value: 1 ether}(
            address(unaiToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        // Roll the block to the future
        vm.roll(block.number + 2);
    }

    function testTransfer() public {
        // Transfer some tokens from owner to user1
        uint256 amount = 1_000_000 * 1e18;
        unaiToken.transfer(user1, amount);

        // Check the balance of user1
        assertEq(unaiToken.balanceOf(user1), amount);
    }

    // Helper function to simulate token purchase
    function buyTokens(address buyer, uint256 ethAmount) private {
        // Deal some ETH to the buyer
        vm.deal(buyer, ethAmount);

        address[] memory path = new address[](2);

        // Buy tokens from the liquidity pool
        vm.startPrank(buyer);
        path[0] = dexRouter.WETH();
        path[1] = address(unaiToken);

        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of tokens
            path,
            buyer,
            block.timestamp
        );
        vm.stopPrank();
    }

    // Helper function to simulate token sale
    function sellTokens(address seller, uint256 tokenAmount) private {
        vm.startPrank(seller);
        unaiToken.approve(address(dexRouter), tokenAmount);

        address[] memory path = new address[](2);

        path[0] = address(unaiToken);
        path[1] = dexRouter.WETH();

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            seller,
            block.timestamp
        );
        vm.stopPrank();
    }
}
