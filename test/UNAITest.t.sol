// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNAITest is Test {
    Contract public unaiToken;
    StakingVault public stakingVault;
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);

    // Setup users
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        // Deploy the UNAI token contract
        unaiToken = new Contract();
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        unaiToken.setStakingContract(address(stakingVault));

        // Enable staking swap
        unaiToken.setSwapStakingEnabled(true);

        // Provide liquidity to the pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount);

        unaiToken.approve(address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{value: 1 ether}(
            address(unaiToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        // Enable trading
        unaiToken.enableTrading(1);

        // Remove limits to test unrestricted buys and sells
        unaiToken.removeLimits();

        // Roll the block to the future
        vm.roll(block.number + 2);
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

    function test_StakingRewardsFeeOnSell() public {
        // Disable swapBack
        unaiToken.setSwapEnabled(false);

        uint256 sellAmount = 1000 * 1e18;

        // User1 buys tokens
        buyTokens(user1, 1 ether);
        uint256 initialBalanceUser1 = unaiToken.balanceOf(user1);
        assertGt(initialBalanceUser1, 0, "User1 should have some tokens after buying");

        // Get initial contract balances before sell
        uint256 initialStakingRewardsTokens = unaiToken.tokensForStaking();
        uint256 initialContractBalance = unaiToken.balanceOf(address(unaiToken));

        // Add logging to check initial balances
        console.log("Initial contract token balance:", initialContractBalance);
        console.log("Initial staking rewards tokens:", initialStakingRewardsTokens);

        // Simulate a sell transaction and ensure fees are applied
        sellTokens(user1, sellAmount);

        // Check that the contract's token balance has increased due to fees
        uint256 finalContractBalance = unaiToken.balanceOf(address(unaiToken));
        uint256 finalStakingRewardsTokens = unaiToken.tokensForStaking();

        // Log final balances after the sell
        console.log("Final contract token balance:", finalContractBalance);
        console.log("Final staking rewards tokens:", finalStakingRewardsTokens);

        // Check that the contract's token balance increased
        assertGt(
            finalContractBalance,
            initialContractBalance,
            "Contract should have more tokens after sell due to fees"
        );

        // Check that the staking rewards tokens have increased
        assertGt(
            finalStakingRewardsTokens,
            initialStakingRewardsTokens,
            "Staking rewards tokens should increase after sell"
        );

        // Corrected fee calculation
        uint256 expectedStakingFee = sellAmount * unaiToken.sellStakingRewardsFee() / 100;

        console.log("Expected staking rewards fee:", expectedStakingFee);
        console.log(
            "Actual staking rewards fee:", finalStakingRewardsTokens - initialStakingRewardsTokens
        );

        assertEq(
            finalStakingRewardsTokens - initialStakingRewardsTokens,
            expectedStakingFee,
            "Staking rewards fee should be deducted correctly"
        );
    }

    function test_StakingRewardsDistribution() public {
        uint256 sellAmount = 1000 * 1e18;

        // Lower the swap threshold to allow the swap to happen
        unaiToken.updateSwapTokensAtAmount(1000 ether); // Set a lower threshold

        // User1 buys tokens and then sells them
        buyTokens(user1, 1 ether);
        sellTokens(user1, sellAmount);

        // Check that the contract has accumulated staking rewards tokens
        uint256 stakingRewardsTokens = unaiToken.tokensForStaking();
        assertGt(stakingRewardsTokens, 0, "Staking rewards tokens should accumulate after sell");

        // Simulate swapping tokens for ETH (this would trigger reward distribution)
        unaiToken.forceSwapBack();

        // Check if staking rewards tokens are reset after distribution
        uint256 finalStakingRewardsTokens = unaiToken.tokensForStaking();
        assertEq(
            finalStakingRewardsTokens,
            0,
            "Staking rewards tokens should be reset after distribution"
        );
    }

    function test_UpdateSellStakingRewardsFee() public {
        // Owner updates the staking rewards fee
        uint256 newStakingRewardsFee = 3; // Change to 3%
        unaiToken.updateSellFees(2, 1, 0, 0, newStakingRewardsFee);

        // Check that the new sellStakingRewardsFee is correctly set
        uint256 updatedStakingRewardsFee = unaiToken.sellStakingRewardsFee();
        assertEq(
            updatedStakingRewardsFee,
            newStakingRewardsFee,
            "The sellStakingRewardsFee should be updated to 3%"
        );
    }

    function test_SellWithUpdatedStakingRewardsFee() public {
        // Owner updates the staking rewards fee to 4%
        uint256 newStakingRewardsFee = 4;
        unaiToken.updateSellFees(2, 1, 0, 0, newStakingRewardsFee);

        uint256 sellAmount = 1000 * 1e18;

        // User1 buys tokens and then sells them
        buyTokens(user1, 1 ether);
        uint256 initialStakingRewardsTokens = unaiToken.tokensForStaking();

        // Add logging to debug fee calculation
        uint256 sellTotalFees = unaiToken.sellTotalFees();
        uint256 stakingRewardsFee = unaiToken.sellStakingRewardsFee();

        console.log("Sell amount:", sellAmount);
        console.log("Sell total fees:", sellTotalFees);
        console.log("Staking rewards fee:", stakingRewardsFee);
        assertTrue(sellTotalFees > 0, "Sell total fees should be greater than 0");

        // Simulate a sell
        sellTokens(user1, sellAmount);

        // Check that the staking rewards tokens have increased correctly
        uint256 finalStakingRewardsTokens = unaiToken.tokensForStaking();
        uint256 expectedStakingFee = sellAmount * stakingRewardsFee / 100;
        assertEq(
            finalStakingRewardsTokens - initialStakingRewardsTokens,
            expectedStakingFee,
            "Staking rewards tokens should increase according to the updated fee"
        );
    }

    function test_StakingRewardsAccumulateWithoutSwap() public {
        // Initially set swapStakingEnabled to false
        unaiToken.setSwapStakingEnabled(false);

        // Set a lower swap threshold to easily trigger the swap
        unaiToken.updateSwapTokensAtAmount(1000 ether);

        uint256 sellAmount = 1000 ether;

        // User1 buys tokens and then sells them
        buyTokens(user1, 1 ether);
        uint256 initialStakingRewardsTokens = unaiToken.tokensForStaking();
        uint256 initialContractEthBalance = address(unaiToken).balance;

        // Perform a token sale
        sellTokens(user1, sellAmount);

        // Check that staking rewards tokens have accumulated
        uint256 finalStakingRewardsTokens = unaiToken.tokensForStaking();
        assertGt(
            finalStakingRewardsTokens,
            initialStakingRewardsTokens,
            "Staking rewards tokens should accumulate after the sell"
        );

        // Track the staking reward ETH balance before and after swap
        uint256 stakingEthBalanceBeforeSwap = address(stakingVault).balance;

        // Simulate forceSwapBack to check if staking rewards are distributed
        unaiToken.forceSwapBack();

        // Check the staking contract's ETH balance (it should remain unchanged)
        uint256 stakingEthBalanceAfterSwap = address(stakingVault).balance;
        assertEq(
            stakingEthBalanceBeforeSwap,
            stakingEthBalanceAfterSwap,
            "Staking contract ETH balance should not increase because staking swap is disabled"
        );

        // Verify staking rewards tokens were not swapped out
        assertGt(
            unaiToken.tokensForStaking(),
            0,
            "Staking rewards tokens should still be present because no swap occurred"
        );
    }

    function test_StakingRewardsSwapWhenEnabled() public {
        // Set a lower swap threshold to easily trigger the swap
        unaiToken.updateSwapTokensAtAmount(1000 ether);

        uint256 sellAmount = 1000 ether;

        // User1 buys tokens and then sells them
        buyTokens(user1, 1 ether);
        uint256 initialStakingRewardsTokens = unaiToken.tokensForStaking();
        uint256 initialContractEthBalance = address(unaiToken).balance;

        // Perform a token sale
        sellTokens(user1, sellAmount);

        // Check that staking rewards tokens have accumulated
        uint256 finalStakingRewardsTokens = unaiToken.tokensForStaking();
        assertGt(
            finalStakingRewardsTokens,
            initialStakingRewardsTokens,
            "Staking rewards tokens should accumulate after the sell"
        );

        // Simulate forceSwapBack to trigger the swap
        unaiToken.forceSwapBack();

        // Check that ETH balance of contract increased due to staking rewards swap
        uint256 finalContractEthBalance = address(unaiToken).balance;
        assertGt(
            finalContractEthBalance,
            initialContractEthBalance,
            "Contract ETH balance should increase because staking swap is enabled"
        );

        // Verify staking rewards tokens were swapped out
        assertEq(unaiToken.tokensForStaking(), 0, "Staking rewards tokens should be swapped out");
    }
}
