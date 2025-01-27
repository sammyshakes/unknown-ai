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

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract UNAITest is Test {
    Contract public unaiToken;
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);
    IUniswapV2Factory uniswapFactory = IUniswapV2Factory(dexRouter.factory());

    // Setup users
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    address public operationsAddress = address(0x3);
    address public devAddress = address(0x4);

    function setUp() public {
        // Deploy the UNAI token contract
        unaiToken = new Contract(operationsAddress, devAddress);

        // Create LP Pair
        address lpPair = uniswapFactory.createPair(address(unaiToken), dexRouter.WETH());

        // Provide liquidity to the pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount);

        require(unaiToken.balanceOf(address(this)) >= tokenAmount, "Insufficient token balance");
        unaiToken.approve(address(dexRouter), type(uint256).max);

        dexRouter.addLiquidityETH{value: 1 ether}(
            address(unaiToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        unaiToken.setLpPair(lpPair);

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

    function testBuyFees() public {
        uint256 ethAmount = 1 ether;

        buyTokens(user1, ethAmount);

        // Check fee accumulation
        uint256 opsTokens = unaiToken.tokensForOperations();
        uint256 devTokens = unaiToken.tokensForDev();

        assertGt(opsTokens, 0, "Ops fees not collected");
        assertGt(devTokens, 0, "Dev fees not collected");

        // Calculate expected fee ratio (3:1 for ops:dev)
        uint256 buyOpsFee = unaiToken.buyOperationsFee();
        uint256 buyDevFee = unaiToken.buyDevFee();

        // Allow for 2 wei rounding difference
        uint256 expectedOpsRatio = buyOpsFee * devTokens;
        uint256 expectedDevRatio = buyDevFee * opsTokens;
        assertApproxEqAbs(expectedOpsRatio, expectedDevRatio, 2, "Fee ratio mismatch");
    }

    function testSellFees() public {
        // First buy some tokens
        buyTokens(user1, 1 ether);
        uint256 userBalance = unaiToken.balanceOf(user1);

        vm.startPrank(user1);
        unaiToken.approve(address(dexRouter), userBalance);

        sellTokens(user1, userBalance);

        assertGt(unaiToken.tokensForOperations(), 0, "Ops fees not collected on sell");
        assertGt(unaiToken.tokensForDev(), 0, "Dev fees not collected on sell");
    }

    function testFeeDistribution() public {
        // First do multiple buys to accumulate fees
        buyTokens(user1, 2 ether);
        buyTokens(user2, 2 ether);

        // Get initial ETH balances
        uint256 initialOpsEth = operationsAddress.balance;
        uint256 initialDevEth = devAddress.balance;

        // Force swap with minimum threshold
        vm.startPrank(owner);
        unaiToken.setSwapTokensAtAmount(1); // Set to minimum to trigger swap
        vm.stopPrank();

        // Sell tokens to trigger the swap
        uint256 userBalance = unaiToken.balanceOf(user1);
        vm.startPrank(user1);
        unaiToken.approve(address(dexRouter), userBalance);
        sellTokens(user1, userBalance / 2); // Sell half the tokens
        vm.stopPrank();

        // Wait for a block to ensure ETH transfers are processed
        vm.roll(block.number + 1);

        // Verify ETH distributions
        uint256 finalOpsEth = operationsAddress.balance;
        uint256 finalDevEth = devAddress.balance;

        // Check that both addresses received ETH
        uint256 opsEthReceived = finalOpsEth - initialOpsEth;
        uint256 devEthReceived = finalDevEth - initialDevEth;

        assertGt(opsEthReceived, 0, "No ETH sent to ops");
        assertGt(devEthReceived, 0, "No ETH sent to dev");

        // Verify fee ratio (3:1)
        // Allow for 5 wei rounding difference due to division and price impact
        uint256 expectedOpsRatio = 3 * devEthReceived;
        uint256 expectedDevRatio = 1 * opsEthReceived;
        assertApproxEqAbs(expectedOpsRatio, expectedDevRatio, 5, "ETH ratio mismatch");
    }

    function testOnlyOwnerCanUpdateFees() public {
        vm.startPrank(user1);
        vm.expectRevert();
        unaiToken.updateBuyFees(2, 2);
        vm.expectRevert();
        unaiToken.updateSellFees(2, 2);
        vm.stopPrank();
    }

    function testFeeUpdates() public {
        uint256 newBuyOps = 2;
        uint256 newBuyDev = 2;
        uint256 newSellOps = 4;
        uint256 newSellDev = 1;

        vm.startPrank(owner);
        unaiToken.updateBuyFees(newBuyOps, newBuyDev);
        unaiToken.updateSellFees(newSellOps, newSellDev);
        vm.stopPrank();

        assertEq(unaiToken.buyOperationsFee(), newBuyOps, "Buy ops fee not updated");
        assertEq(unaiToken.buyDevFee(), newBuyDev, "Buy dev fee not updated");
        assertEq(unaiToken.sellOperationsFee(), newSellOps, "Sell ops fee not updated");
        assertEq(unaiToken.sellDevFee(), newSellDev, "Sell dev fee not updated");
    }

    function testPreventInvalidFeeUpdates() public {
        vm.startPrank(owner);
        vm.expectRevert("Buy fees cannot exceed 10%");
        unaiToken.updateBuyFees(8, 3); // 11% total

        vm.expectRevert("Sell fees cannot exceed 10%");
        unaiToken.updateSellFees(9, 2); // 11% total
        vm.stopPrank();
    }

    function testAddressUpdates() public {
        address newOps = address(0x5);
        address newDev = address(0x6);

        vm.startPrank(owner);
        unaiToken.updateOperationsAddress(newOps);
        unaiToken.updateDevAddress(newDev);
        vm.stopPrank();

        assertEq(unaiToken.operationsAddress(), newOps, "Ops address not updated");
        assertEq(unaiToken.devAddress(), newDev, "Dev address not updated");
    }

    function testSwapThreshold() public {
        uint256 newThreshold = 100_000 * 1e18;

        vm.startPrank(owner);
        unaiToken.setSwapTokensAtAmount(newThreshold);
        vm.stopPrank();

        assertEq(unaiToken.swapTokensAtAmount(), newThreshold, "Swap threshold not updated");
    }

    function testSwapEnabled() public {
        // First accumulate some fees
        buyTokens(user1, 1 ether);

        // Disable swapping
        vm.startPrank(owner);
        unaiToken.setSwapEnabled(false);
        unaiToken.setSwapTokensAtAmount(1); // Set low threshold
        vm.stopPrank();

        // Try to sell - should not trigger swap
        uint256 userBalance = unaiToken.balanceOf(user1);
        uint256 initialOpsEth = operationsAddress.balance;
        uint256 initialDevEth = devAddress.balance;

        vm.startPrank(user1);
        unaiToken.approve(address(dexRouter), userBalance);
        sellTokens(user1, userBalance / 2);
        vm.stopPrank();

        // Verify no ETH was distributed
        assertEq(
            operationsAddress.balance, initialOpsEth, "Ops received ETH when swapping disabled"
        );
        assertEq(devAddress.balance, initialDevEth, "Dev received ETH when swapping disabled");
    }

    function testContractExcludedFromFees() public {
        // First buy some tokens to accumulate fees
        buyTokens(user1, 1 ether);

        // Get initial fee counters
        uint256 initialOpsTokens = unaiToken.tokensForOperations();
        uint256 initialDevTokens = unaiToken.tokensForDev();

        // Transfer tokens to user2 from contract
        uint256 amount = 1_000_000 * 1e18;
        vm.startPrank(owner);
        unaiToken.transfer(address(unaiToken), amount);
        vm.stopPrank();

        // Contract sends tokens to user2
        vm.prank(owner);
        unaiToken.transfer(user2, amount);

        // Verify no additional fees were taken
        assertEq(
            unaiToken.tokensForOperations(), initialOpsTokens, "Ops fees collected from contract"
        );
        assertEq(unaiToken.tokensForDev(), initialDevTokens, "Dev fees collected from contract");
        assertEq(unaiToken.balanceOf(user2), amount, "Fees taken when contract sent tokens");
    }

    function testConstructorZeroAddressValidation() public {
        vm.expectRevert("Ops address cannot be zero");
        new Contract(address(0), devAddress);

        vm.expectRevert("Dev address cannot be zero");
        new Contract(operationsAddress, address(0));
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
