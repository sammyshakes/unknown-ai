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

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

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
        (uint256 amount2, uint256 startTime2, uint256 duration2, uint256 shares2,) =
            stakingVault.userStakes(user2, 0);
        assertEq(amount2, stakeAmount);
        assertEq(duration2, lockDuration);
        assertEq(shares2, stakeAmount); // Because lockDuration == SHARE_TIME_FRAME
    }

    function test_MultipleStakesRewards() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration1 = 90 days;
        uint256 lockDuration2 = 180 days;

        // User1 buys tokens
        buyTokens(user1, 2 ether);

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount * 2);
        stakingVault.stake(stakeAmount, lockDuration1);
        stakingVault.stake(stakeAmount, lockDuration2);
        vm.stopPrank();

        // Add rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Warp time to after first lock period
        vm.warp(block.timestamp + lockDuration1);

        // Update rewards
        stakingVault.updateRewards();

        uint256 rewards1 = stakingVault.pendingRewards(user1, 0);
        uint256 rewards2 = stakingVault.pendingRewards(user1, 1);

        console.log("Rewards for 90-day stake:", rewards1);
        console.log("Rewards for 180-day stake:", rewards2);

        assertTrue(rewards2 > rewards1, "Longer lock duration should yield more rewards");

        // Claim rewards for both stakes
        vm.startPrank(user1);
        uint256 initialBalance = user1.balance;
        stakingVault.claimRewards(0);
        stakingVault.claimRewards(1);
        uint256 finalBalance = user1.balance;
        vm.stopPrank();

        uint256 totalRewardsClaimed = finalBalance - initialBalance;
        console.log("Total rewards claimed:", totalRewardsClaimed);

        assertTrue(totalRewardsClaimed > 0, "User1 should have received ETH rewards");
    }
}
