// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingVault is Ownable, ReentrancyGuard {
    IERC20 public unaiToken;

    struct Pool {
        uint256 lockPeriod;
        uint256 accETHPerShare;
        uint256 totalStaked;
        uint256 lastRewardTime;
        uint256 lastRewardBalance;
        uint256 weight;
    }

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
        address owner;
        uint256 lockEndTime;
    }

    Pool[] public pools;
    mapping(address => mapping(uint256 => Stake[])) public stakes;
    mapping(address => address) public stakeApprovals;
    mapping(address => bool) public authorizedMarketplaces;

    uint256 public totalStaked;

    event PoolAdded(uint256 indexed poolId, uint256 lockPeriod);
    event Staked(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 amount
    );
    event Unstaked(
        address indexed user,
        uint256 indexed poolId,
        uint256 indexed stakeId,
        uint256 stakedAmount,
        uint256 rewardAmount
    );
    event RewardsDistributed(uint256 indexed poolId, uint256 totalRewards);
    event RewardsClaimed(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 reward
    );
    event RewardsPaidIn(uint256 amount);
    event StakeTransferred(
        address indexed from, address indexed to, uint256 indexed poolId, uint256 stakeId
    );
    event MarketplaceAuthorizationSet(address indexed marketplace, bool isAuthorized);

    constructor(IERC20 _unaiToken) Ownable(msg.sender) {
        unaiToken = _unaiToken;
    }

    function addPool(uint256 lockPeriod, uint256 weight) external onlyOwner {
        pools.push(
            Pool({
                lockPeriod: lockPeriod,
                accETHPerShare: 0,
                totalStaked: 0,
                lastRewardTime: block.timestamp,
                lastRewardBalance: 0,
                weight: weight
            })
        );
        emit PoolAdded(pools.length - 1, lockPeriod);
    }

    function updatePool(uint256 poolId, bool isDistributing) public {
        Pool storage pool = pools[poolId];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.totalStaked;
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 rewardAmount = pool.lastRewardBalance;
        if (rewardAmount > 0) {
            pool.accETHPerShare += (rewardAmount * 1e18) / tokenSupply;
        }
        pool.lastRewardTime = block.timestamp;

        if (isDistributing) {
            pool.lastRewardBalance = 0;
        }

        // Debug: Log updated pool values
        emit PoolUpdated(
            poolId,
            pool.accETHPerShare,
            pool.totalStaked,
            pool.lastRewardTime,
            pool.lastRewardBalance
        );
    }

    event PoolUpdated(
        uint256 indexed poolId,
        uint256 accETHPerShare,
        uint256 totalStaked,
        uint256 lastRewardTime,
        uint256 lastRewardBalance
    );

    function distributeRewards() public payable {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            totalWeight += pools[i].weight;
        }

        for (uint256 i = 0; i < pools.length; i++) {
            Pool storage pool = pools[i];
            uint256 poolReward = (msg.value * pool.weight) / totalWeight;
            pool.lastRewardBalance += poolReward;
            updatePool(i, true); // Reset after distribution
        }

        emit RewardsPaidIn(msg.value);
    }

    function stake(uint256 poolId, uint256 amount) external nonReentrant {
        updatePool(poolId, false);
        Pool storage pool = pools[poolId];
        uint256 lockEndTime = block.timestamp + pool.lockPeriod;

        stakes[msg.sender][poolId].push(
            Stake({
                amount: amount,
                rewardDebt: amount * pool.accETHPerShare / 1e18,
                owner: msg.sender,
                lockEndTime: lockEndTime
            })
        );

        unaiToken.transferFrom(msg.sender, address(this), amount);
        pool.totalStaked += amount; // Update the total staked in the pool
        totalStaked += amount; // Update the total staked in the contract

        emit Staked(msg.sender, poolId, stakes[msg.sender][poolId].length - 1, amount);
    }

    function unstake(uint256 poolId, uint256 stakeId) external nonReentrant {
        require(poolId < pools.length, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];

        require(userStake.owner == msg.sender, "Not the owner of this stake");
        require(block.timestamp >= userStake.lockEndTime, "Lock period not over");

        uint256 amount = userStake.amount;
        require(amount <= pool.totalStaked, "Staked amount exceeds total staked in pool");

        // Update pool to get the latest accETHPerShare
        updatePool(poolId, false);

        uint256 accETHPerShare = pool.accETHPerShare;
        uint256 rewardDebt = userStake.rewardDebt;

        // Debug: Log intermediate values
        emit LogValues(accETHPerShare, amount, rewardDebt);

        uint256 pending = 0;
        if (accETHPerShare > rewardDebt) {
            pending = (amount * (accETHPerShare - rewardDebt)) / 1e18;
        }

        // Debug: Log calculated pending reward
        emit CalculatedReward(pending);

        // Ensure pending rewards are non-negative
        require(pending >= 0, "Pending reward calculation resulted in underflow");

        pool.totalStaked -= amount; // Update the total staked in the pool
        totalStaked -= amount; // Update the total staked in the contract
        delete stakes[msg.sender][poolId][stakeId];

        unaiToken.transfer(msg.sender, amount);

        if (pending > 0) {
            (bool success,) = msg.sender.call{value: pending}("");
            require(success, "ETH transfer failed");
        }

        emit Unstaked(msg.sender, poolId, stakeId, amount, pending);
    }

    event CalculatedReward(uint256 pending);

    event LogValues(uint256 accETHPerShare, uint256 amount, uint256 rewardDebt);

    function claimRewards(uint256 poolId, uint256 stakeId) external nonReentrant {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");

        updatePool(poolId, false);
        Pool storage pool = pools[poolId];

        uint256 pending = (userStake.amount * pool.accETHPerShare) / 1e18 - userStake.rewardDebt;
        if (pending > 0) {
            (bool success,) = msg.sender.call{value: pending}("");
            require(success, "ETH transfer failed");
            emit RewardsClaimed(msg.sender, poolId, stakeId, pending);
        }

        userStake.rewardDebt = userStake.amount * pool.accETHPerShare / 1e18;
    }

    function pendingRewards(address user, uint256 poolId, uint256 stakeId)
        external
        view
        returns (uint256)
    {
        Stake storage userStake = stakes[user][poolId][stakeId];
        Pool storage pool = pools[poolId];

        uint256 accETHPerShare = pool.accETHPerShare;
        uint256 rewardDebt = userStake.rewardDebt;
        uint256 amount = userStake.amount;

        uint256 pending = (amount * accETHPerShare / 1e18) - rewardDebt;

        return pending;
    }

    function transferStake(address from, address to, uint256 poolId, uint256 stakeId) external {
        require(authorizedMarketplaces[msg.sender], "Caller is not an authorized marketplace");

        Stake storage fromStake = stakes[from][poolId][stakeId];
        require(fromStake.owner == from, "Not the owner of this stake");

        updatePool(poolId, false);

        Stake memory newStake = fromStake;
        newStake.owner = to; // Update the owner of the new stake
        stakes[to][poolId].push(newStake);

        delete stakes[from][poolId][stakeId]; // Remove the stake from the original owner

        emit StakeTransferred(from, to, poolId, stakeId);
    }

    function estimateAPY(uint256 poolId, uint256 observationPeriod)
        external
        view
        returns (uint256)
    {
        uint256 rewardsPerShare = pools[poolId].accETHPerShare;

        // Annualize the rewards per share
        uint256 annualizedRewardsPerShare = (rewardsPerShare * 365 days) / observationPeriod;

        // Calculate APY
        uint256 apy = (annualizedRewardsPerShare * 100) / 1e18;
        return apy;
    }

    function setMarketplaceAuthorization(address marketplace, bool isAuthorized)
        external
        onlyOwner
    {
        authorizedMarketplaces[marketplace] = isAuthorized;
        emit MarketplaceAuthorizationSet(marketplace, isAuthorized);
    }

    receive() external payable {
        distributeRewards();
    }
}
