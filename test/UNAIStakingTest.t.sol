// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingVault} from "../src/UNAIStaking.sol";
import {Contract, IDexRouter, IERC20} from "../src/UNAI.sol";

contract UNAIStakingTest is Test {
    StakingVault public stakingVault;
    Contract public unaiToken; // This is the UNAI token used for staking and rewards

    // dex router address
    // address public router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        // Deploy the UNAI token
        unaiToken = new Contract();

        // Deploy the StakingVault contract
        stakingVault = new StakingVault(IERC20(address(unaiToken)), IERC20(address(unaiToken)));

        // Transfer UNAI tokens to users for testing
        unaiToken.transfer(user1, 1000 * 1e18);
        unaiToken.transfer(user2, 1000 * 1e18);
        unaiToken.transfer(owner, 1000 * 1e18);

        // Add pools
        stakingVault.addPool(180 days); // 6-month lock period
    }

    function test_StakeAndUnstake() public {
        uint256 poolId = 0;

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18, true);
        vm.stopPrank();

        // Check the stake
        (
            uint256 amount,
            uint256 rewardDebt,
            bool autoCompounding,
            address stakeOwner,
            uint256 lockEndTime
        ) = stakingVault.stakes(user1, poolId, 0);
        assertEq(amount, 100 * 1e18);
        assertEq(stakeOwner, user1);

        // Fast forward 6 months
        vm.warp(block.timestamp + 180 days);

        // Unstake tokens
        vm.startPrank(user1);
        stakingVault.unstake(poolId, 0);
        vm.stopPrank();

        // Check the stake
        (amount, rewardDebt, autoCompounding, stakeOwner, lockEndTime) =
            stakingVault.stakes(user1, poolId, 0);
        assertEq(amount, 0);
        assertEq(stakeOwner, address(0));
    }

    function test_ClaimRewards() public {
        uint256 poolId = 0;

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18, true);
        vm.stopPrank();

        // Pay rewards into the vault
        vm.startPrank(owner);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.payRewards(100 * 1e18);
        vm.stopPrank();

        // Fast forward 6 months
        vm.warp(block.timestamp + 180 days);

        // Claim rewards
        vm.startPrank(user1);
        stakingVault.claimRewards(poolId, 0);
        vm.stopPrank();

        // Check the rewards
        uint256 user1RewardsBalance = unaiToken.balanceOf(user1);
        assertEq(user1RewardsBalance, 100 * 1e18);
    }

    function test_AutoCompound() public {
        uint256 poolId = 0;

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18, true);
        vm.stopPrank();

        // Pay rewards into the vault
        vm.startPrank(owner);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.payRewards(100 * 1e18);
        vm.stopPrank();

        // Fast forward 6 months
        vm.warp(block.timestamp + 180 days);

        // Auto-compound rewards
        vm.startPrank(user1);
        stakingVault.autoCompound(poolId, 0);
        vm.stopPrank();

        // Check the auto-compounded amount
        (uint256 amount,,,) = stakingVault.stakes(user1, poolId, 0);
        assertEq(amount, 200 * 1e18); // Initial 100 amount + 100 from auto-compounded rewards
    }

    function test_ChangeAutoCompoundingStatus() public {
        uint256 poolId = 0;

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18, true);
        vm.stopPrank();

        // Change auto-compounding status
        vm.startPrank(user1);
        stakingVault.changeAutoCompoundingStatus(poolId, 0, false);
        vm.stopPrank();

        // Verify auto-compounding status changed
        (,, bool autoCompounding,,) = stakingVault.stakes(user1, poolId, 0);
        assertEq(autoCompounding, false);
    }

    function test_StakeTransfer() public {
        uint256 poolId = 0;

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18, true);
        vm.stopPrank();

        // Approve transfer of the stake
        vm.startPrank(user1);
        stakingVault.approveStakeTransfer(user2, poolId, 0);
        vm.stopPrank();

        // Transfer the stake
        vm.startPrank(user2);
        stakingVault.transferStake(user1, user2, poolId, 0);
        vm.stopPrank();

        // Check the new owner of the stake
        (,,, address newOwner,) = stakingVault.stakes(user2, poolId, 0);
        assertEq(newOwner, user2);
    }
}
