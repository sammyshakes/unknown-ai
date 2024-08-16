// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingVault is Ownable, ReentrancyGuard {
    IERC20 public unaiToken;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockDuration;
        uint256 shares;
        uint256 rewardDebt;
    }

    uint256 public constant SHARE_TIME_FRAME = 90 days;
    uint256 public totalShares;
    uint256 public accRewardPerShare;
    uint256 public lastUpdateTime;
    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;

    mapping(address => Stake[]) public userStakes;
    mapping(address => address) public stakeApprovals;
    mapping(address => bool) public authorizedMarketplaces;

    event Staked(
        address indexed user, uint256 indexed stakeId, uint256 amount, uint256 lockDuration
    );
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 reward);
    event RewardsDistributed(uint256 totalRewards);
    event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event StakeTransferred(address indexed from, address indexed to, uint256 stakeId);
    event MarketplaceAuthorizationSet(address indexed marketplace, bool isAuthorized);

    constructor(IERC20 _unaiToken) Ownable(msg.sender) {
        unaiToken = _unaiToken;
        lastUpdateTime = block.timestamp;
    }

    function updateRewards() public {
        if (block.timestamp <= lastUpdateTime || totalShares == 0) {
            return;
        }

        uint256 newRewards;
        if (address(this).balance > totalRewardsDistributed) {
            newRewards = address(this).balance - totalRewardsDistributed;
        } else {
            newRewards = 0;
        }

        if (newRewards > 0) {
            accRewardPerShare += (newRewards * 1e18) / totalShares;
            totalRewardsDistributed += newRewards;
        }
        lastUpdateTime = block.timestamp;
    }

    function stake(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockDuration >= 30 days, "Lock duration must be at least 30 days");

        updateRewards();

        uint256 shares = (amount * lockDuration) / SHARE_TIME_FRAME;
        Stake memory newStake = Stake({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            shares: shares,
            rewardDebt: (shares * accRewardPerShare) / 1e18
        });

        userStakes[msg.sender].push(newStake);
        totalShares += shares;
        totalStaked += amount;

        unaiToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, userStakes[msg.sender].length - 1, amount, lockDuration);
    }

    function unstake(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage userStake = userStakes[msg.sender][stakeId];
        require(
            block.timestamp >= userStake.startTime + userStake.lockDuration, "Lock period not over"
        );

        updateRewards();

        uint256 amount = userStake.amount;
        uint256 shares = userStake.shares;
        uint256 pending = _calculateRewards(shares, userStake.rewardDebt);

        totalShares -= shares;
        totalStaked -= amount;

        // Remove the stake by swapping with the last element and popping
        userStakes[msg.sender][stakeId] = userStakes[msg.sender][userStakes[msg.sender].length - 1];
        userStakes[msg.sender].pop();

        unaiToken.transfer(msg.sender, amount);

        if (pending > 0) {
            (bool success,) = msg.sender.call{value: pending}("");
            require(success, "ETH transfer failed");
        }

        emit Unstaked(msg.sender, stakeId, amount, pending);
    }

    function claimRewards(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage userStake = userStakes[msg.sender][stakeId];

        updateRewards();

        uint256 pending = _calculateRewards(userStake.shares, userStake.rewardDebt);
        if (pending > 0) {
            userStake.rewardDebt = (userStake.shares * accRewardPerShare) / 1e18;
            (bool success,) = msg.sender.call{value: pending}("");
            require(success, "ETH transfer failed");
            emit RewardsClaimed(msg.sender, stakeId, pending);
        }
    }

    function pendingRewards(address user, uint256 stakeId) external view returns (uint256) {
        require(stakeId < userStakes[user].length, "Invalid stake ID");
        Stake storage userStake = userStakes[user][stakeId];

        uint256 _accRewardPerShare = accRewardPerShare;

        uint256 newRewards;
        if (address(this).balance > totalRewardsDistributed) {
            newRewards = address(this).balance - totalRewardsDistributed;
        } else {
            newRewards = 0;
        }

        if (newRewards > 0 && totalShares > 0) {
            _accRewardPerShare += (newRewards * 1e18) / totalShares;
        }

        uint256 rewards = (userStake.shares * _accRewardPerShare) / 1e18;
        if (rewards <= userStake.rewardDebt) {
            return 0;
        }
        return rewards - userStake.rewardDebt;
    }

    function _calculateRewards(uint256 shares, uint256 rewardDebt)
        internal
        view
        returns (uint256)
    {
        return _calculateRewards(shares, rewardDebt, accRewardPerShare);
    }

    function _calculateRewards(uint256 shares, uint256 rewardDebt, uint256 _accRewardPerShare)
        internal
        pure
        returns (uint256)
    {
        uint256 rewards = (shares * _accRewardPerShare) / 1e18;
        if (rewards <= rewardDebt) {
            return 0;
        }
        return rewards - rewardDebt;
    }

    function transferStake(address from, address to, uint256 stakeId) external {
        require(authorizedMarketplaces[msg.sender], "Caller is not an authorized marketplace");
        require(stakeId < userStakes[from].length, "Invalid stake ID");

        updateRewards();

        Stake storage transferredStake = userStakes[from][stakeId];
        uint256 pending = _calculateRewards(transferredStake.shares, transferredStake.rewardDebt);

        // Transfer any pending rewards to the original owner
        if (pending > 0) {
            (bool success,) = from.call{value: pending}("");
            require(success, "ETH transfer failed");
        }

        // Reset the reward debt for the new owner
        transferredStake.rewardDebt = (transferredStake.shares * accRewardPerShare) / 1e18;

        userStakes[to].push(transferredStake);

        // Remove the stake from the original owner
        userStakes[from][stakeId] = userStakes[from][userStakes[from].length - 1];
        userStakes[from].pop();

        emit StakeTransferred(from, to, stakeId);
    }

    function setMarketplaceAuthorization(address marketplace, bool isAuthorized)
        external
        onlyOwner
    {
        authorizedMarketplaces[marketplace] = isAuthorized;
        emit MarketplaceAuthorizationSet(marketplace, isAuthorized);
    }

    receive() external payable {
        emit RewardsDistributed(msg.value);
    }
}
