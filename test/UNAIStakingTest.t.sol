// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";

contract StakingVaultTest is Test {
    StakingVault public stakingVault;
    Contract public unaiToken;

    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);

    // Setup users
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    function setUp() public {
        unaiToken = new Contract();
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        unaiToken.setStakingContract(address(stakingVault));

        // Provide liquidity to the pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount);

        unaiToken.approve(address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{value: 1 ether}(
            address(unaiToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        unaiToken.enableTrading(1);

        // Remove limits
        unaiToken.removeLimits();

        // Roll the block to the future
        vm.roll(block.number + 2);
    }

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

    function test_StakeAndUnstake() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys tokens
        buyTokens(user1, 1 ether);

        console.log("User1 balance before staking:", unaiToken.balanceOf(user1));

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        console.log("User1 balance after staking:", unaiToken.balanceOf(user1));

        (uint256 amount, uint256 startTime, uint256 duration, uint256 shares, uint256 rewardDebt) =
            stakingVault.userStakes(user1, 0);
        console.log("Staked amount:", amount);
        console.log("Start time:", startTime);
        console.log("Lock duration:", duration);
        console.log("Shares:", shares);

        assertEq(amount, stakeAmount);
        assertEq(duration, lockDuration);
        assertEq(shares, stakeAmount); // Because lockDuration == SHARE_TIME_FRAME

        // Add rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Warp time to after lock period
        vm.warp(block.timestamp + lockDuration);

        uint256 initialEthBalance = user1.balance;
        console.log("User1 ETH balance before unstaking:", initialEthBalance);

        vm.prank(user1);
        stakingVault.unstake(0);

        uint256 finalEthBalance = user1.balance;
        console.log("User1 ETH balance after unstaking:", finalEthBalance);
        assertGt(finalEthBalance, initialEthBalance, "User should have received ETH rewards");

        // Check that the stake has been removed
        vm.expectRevert();
        stakingVault.userStakes(user1, 0);
    }

    function test_ClaimRewards() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys tokens
        buyTokens(user1, 1 ether);

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Add rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Warp time to simulate passage of time
        vm.warp(block.timestamp + 30 days);

        // Check initial ETH balance
        uint256 initialEthBalance = user1.balance;
        console.log("Initial ETH balance:", initialEthBalance);

        // Claim rewards
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Check final ETH balance
        uint256 finalEthBalance = user1.balance;
        console.log("Final ETH balance:", finalEthBalance);

        assertTrue(finalEthBalance > initialEthBalance, "User1 should have received ETH rewards");
    }

    function test_TransferStake() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys tokens and stakes
        buyTokens(user1, 1 ether);

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Authorize this contract as a marketplace
        vm.prank(owner);
        stakingVault.setMarketplaceAuthorization(address(this), true);

        // Transfer stake from user1 to user2
        stakingVault.transferStake(user1, user2, 0);

        // Check that user1 no longer has the stake
        vm.expectRevert();
        stakingVault.userStakes(user1, 0);

        // Check that user2 now has the stake
        (uint256 amount2,, uint256 duration2, uint256 shares2,) = stakingVault.userStakes(user2, 0);
        assertEq(amount2, stakeAmount);
        assertEq(duration2, lockDuration);
        assertEq(shares2, stakeAmount); // Because lockDuration == SHARE_TIME_FRAME
    }

    function test_MultipleUsersStakingAndRewards() public {
        // Buy tokens for users
        buyTokens(user1, 5 ether);
        buyTokens(user2, 5 ether);
        buyTokens(user3, 5 ether);

        // Stake different amounts for different durations
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(100 * 1e18, 30 days);
        stakingVault.stake(200 * 1e18, 60 days);
        vm.stopPrank();

        vm.startPrank(user2);
        unaiToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(300 * 1e18, 90 days);
        vm.stopPrank();

        vm.startPrank(user3);
        unaiToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(400 * 1e18, 180 days);
        vm.stopPrank();

        // Add rewards to the staking vault
        uint256 totalRewards = 10 ether;
        vm.deal(address(stakingVault), totalRewards);

        // Advance time
        vm.warp(block.timestamp + 180 days);

        // Update rewards
        stakingVault.updateRewards();

        // Calculate total pending rewards
        uint256 totalPendingRewards = 0;
        for (uint256 i = 0; i < 2; i++) {
            totalPendingRewards += stakingVault.pendingRewards(user1, i);
        }
        totalPendingRewards += stakingVault.pendingRewards(user2, 0);
        totalPendingRewards += stakingVault.pendingRewards(user3, 0);

        console.log("Total pending rewards:", totalPendingRewards);
        console.log("Actual rewards in contract:", address(stakingVault).balance);

        // Ensure total pending rewards don't exceed actual rewards
        assertLe(totalPendingRewards, totalRewards, "Total pending rewards exceed actual rewards");

        // Claim rewards for all users
        uint256 totalClaimedRewards = 0;

        vm.startPrank(user1);
        for (uint256 i = 0; i < 2; i++) {
            uint256 initialBalance = user1.balance;
            stakingVault.claimRewards(i);
            totalClaimedRewards += user1.balance - initialBalance;
        }
        vm.stopPrank();

        vm.prank(user2);
        uint256 initialBalance = user2.balance;
        stakingVault.claimRewards(0);
        totalClaimedRewards += user2.balance - initialBalance;

        vm.prank(user3);
        initialBalance = user3.balance;
        stakingVault.claimRewards(0);
        totalClaimedRewards += user3.balance - initialBalance;

        console.log("Total claimed rewards:", totalClaimedRewards);
        console.log("Remaining rewards in contract:", address(stakingVault).balance);

        // Ensure all rewards are accounted for
        assertEq(
            totalClaimedRewards + address(stakingVault).balance,
            totalRewards,
            "Not all rewards are accounted for"
        );

        // After claiming rewards
        uint256 user1Rewards =
            stakingVault.pendingRewards(user1, 0) + stakingVault.pendingRewards(user1, 1);
        uint256 user2Rewards = stakingVault.pendingRewards(user2, 0);
        uint256 user3Rewards = stakingVault.pendingRewards(user3, 0);

        // Assert that pending rewards are zero or very small
        assertLe(user1Rewards, 1);
        assertLe(user2Rewards, 1);
        assertLe(user3Rewards, 1);

        // Assert that the remaining balance in the contract is small but non-zero
        uint256 remainingBalance = address(stakingVault).balance;
        assertGt(remainingBalance, 0);
        assertLe(remainingBalance, 1000); // Adjust this threshold as needed

        console.log("Remaining balance in contract:", remainingBalance);
    }

    function test_MultipleUsersStakingAndClaimingRewardsAtDifferentTimes() public {
        // User1 stakes 100 tokens for 30 days
        buyTokens(user1, 1 ether);

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100e18);
        stakingVault.stake(100e18, 30 days);
        vm.stopPrank(); // Stop the prank for user1

        // Advance time by 10 days
        vm.warp(block.timestamp + 10 days);

        // User2 stakes 200 tokens for 60 days
        buyTokens(user2, 2 ether);
        vm.startPrank(user2);
        unaiToken.approve(address(stakingVault), 200e18);
        stakingVault.stake(200e18, 60 days);
        vm.stopPrank(); // Stop the prank for user2

        // Advance time by 20 more days (total 30 days from start)
        vm.warp(block.timestamp + 20 days);

        // User1 claims rewards after 30 days
        vm.startPrank(user1);
        stakingVault.claimRewards(0);
        vm.stopPrank(); // Stop the prank for user1

        // Advance time by 30 more days (total 60 days from start)
        vm.warp(block.timestamp + 30 days);

        // User2 claims rewards after 60 days
        vm.startPrank(user2);
        stakingVault.claimRewards(0);
        vm.stopPrank(); // Stop the prank for user2

        // Final checks
        uint256 finalUser1Balance = user1.balance;
        uint256 finalUser2Balance = user2.balance;

        // Assuming the reward calculation logic is correct, the final balances should match the expected rewards
        console.log("User1 Final Balance:", finalUser1Balance);
        console.log("User2 Final Balance:", finalUser2Balance);
    }

    function test_NoRewardsAfterTimelockExpiration() public {
        buyTokens(user1, 1 ether);

        // User1 stakes 100 tokens for 30 days
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100e18);
        stakingVault.stake(100e18, 30 days);
        vm.stopPrank();

        // Advance time by 29 days (just before expiration)
        vm.warp(block.timestamp + 29 days);

        // Check pending rewards just before expiration
        uint256 pendingBeforeExpiration = stakingVault.pendingRewards(user1, 0);
        console.log("Pending rewards before expiration:", pendingBeforeExpiration);

        // Advance time by 2 more days (1 day after expiration)
        vm.warp(block.timestamp + 2 days);

        // Check pending rewards after expiration
        uint256 pendingAfterExpiration = stakingVault.pendingRewards(user1, 0);
        console.log("Pending rewards after expiration:", pendingAfterExpiration);

        // Assert that no additional rewards were accumulated after expiration
        assertEq(pendingAfterExpiration, pendingBeforeExpiration);
    }

    function test_ExtendStake() public {
        buyTokens(user1, 1 ether);

        // User1 stakes 100 tokens for 30 days
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100e18);
        stakingVault.stake(100e18, 30 days);
        vm.stopPrank();

        // Advance time by 10 days
        vm.warp(block.timestamp + 10 days);

        // User1 extends the stake by an additional 30 days
        vm.startPrank(user1);
        stakingVault.extendStake(0, 30 days);
        vm.stopPrank();

        // Advance time by 50 more days (total 60 days from start)
        vm.warp(block.timestamp + 50 days);

        // User1 claims rewards after 60 days
        vm.startPrank(user1);
        stakingVault.claimRewards(0);
        vm.stopPrank();

        // Final checks on the rewards and shares
        uint256 finalUser1Balance = user1.balance;
        console.log("User1 Final Balance after extension:", finalUser1Balance);

        // Assertions can be added to ensure shares and rewards are as expected.
    }

    function test_ExtendStakeRewardAccuracy() public {
        uint256 initialStakeAmount = 100e18;
        uint256 initialLockDuration = 30 days;
        uint256 extensionDuration = 60 days;

        // User1 buys tokens and stakes
        buyTokens(user1, 1 ether);
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), initialStakeAmount);
        stakingVault.stake(initialStakeAmount, initialLockDuration);
        vm.stopPrank();

        console.log("Initial timestamp:", block.timestamp);
        console.log("Initial total shares:", stakingVault.totalShares());

        uint256 totalFees = 0;

        // Simulate transaction fees over 15 days
        for (uint256 i = 0; i < 15; i++) {
            vm.warp(block.timestamp + 1 days);
            uint256 dailyFees = 0.1 ether * (1 + i % 5); // Varying daily fees
            totalFees += dailyFees;

            try vm.deal(address(this), dailyFees) {
                (bool success,) = address(stakingVault).call{value: dailyFees}("");
                require(success, "ETH transfer failed");
            } catch {
                console.log("Failed to send fees on day", i + 1);
            }
        }

        console.log("Timestamp after 15 days:", block.timestamp);
        console.log("Total fees sent in first 15 days:", totalFees);

        // Check pending rewards before extension
        uint256 pendingRewardsBeforeExtension = stakingVault.pendingRewards(user1, 0);
        console.log("Pending rewards before extension:", pendingRewardsBeforeExtension);

        // Extend the stake
        vm.prank(user1);
        stakingVault.extendStake(0, extensionDuration);

        // Check pending rewards immediately after extension
        uint256 pendingRewardsAfterExtension = stakingVault.pendingRewards(user1, 0);
        console.log("Pending rewards after extension:", pendingRewardsAfterExtension);
        console.log("Total shares after extension:", stakingVault.totalShares());

        // Ensure rewards didn't change due to extension
        assertEq(
            pendingRewardsBeforeExtension,
            pendingRewardsAfterExtension,
            "Rewards should not change immediately after extension"
        );

        // Simulate transaction fees over the next 75 days
        for (uint256 i = 0; i < 75; i++) {
            vm.warp(block.timestamp + 1 days);
            uint256 dailyFees = 0.05 ether * (1 + i % 7); // Varying daily fees
            totalFees += dailyFees;

            try vm.deal(address(this), dailyFees) {
                (bool success,) = address(stakingVault).call{value: dailyFees}("");
                require(success, "ETH transfer failed");
            } catch {
                console.log("Failed to send fees on day", i + 16);
            }
        }

        console.log("Final timestamp:", block.timestamp);
        console.log("Total fees sent:", totalFees);

        // Check final pending rewards
        uint256 finalPendingRewards = stakingVault.pendingRewards(user1, 0);
        console.log("Final pending rewards:", finalPendingRewards);

        // Claim rewards and check received amount
        uint256 initialBalance = user1.balance;
        vm.prank(user1);
        stakingVault.claimRewards(0);
        uint256 claimedRewards = user1.balance - initialBalance;

        console.log("Claimed rewards:", claimedRewards);

        // Check that pending rewards are now zero or very small
        uint256 pendingRewardsAfterClaim = stakingVault.pendingRewards(user1, 0);
        console.log("Pending rewards after claim:", pendingRewardsAfterClaim);
        assertLe(pendingRewardsAfterClaim, 1e14, "Pending rewards after claim should be very small");

        // Verify total rewards distributed
        uint256 remainingBalance = address(stakingVault).balance;
        console.log("Remaining balance in staking vault:", remainingBalance);
        assertApproxEqRel(
            claimedRewards + remainingBalance,
            totalFees,
            1e16,
            "Total distributed rewards should match total fees sent"
        );
    }
}
