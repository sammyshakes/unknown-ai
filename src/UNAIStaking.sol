// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingVault is Ownable, ReentrancyGuard {
    IERC20 public stakingToken;
    IERC20 public rewardsToken;

    struct Pool {
        uint256 lockPeriod;
        uint256 accUNAIPerShare;
        uint256 totalStaked;
        uint256 lastRewardTime;
    }

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
        bool autoCompounding;
        address owner;
        uint256 lockEndTime;
    }

    Pool[] public pools;
    mapping(address => mapping(uint256 => Stake[])) public stakes;
    mapping(address => address) public stakeApprovals;

    event PoolAdded(uint256 indexed poolId, uint256 lockPeriod);
    event Staked(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 amount
    );
    event Unstaked(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 amount
    );
    event RewardsDistributed(uint256 indexed poolId, uint256 totalRewards);
    event RewardsClaimed(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 reward
    );
    event AutoCompounded(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, uint256 reward
    );
    event AutoCompoundingStatusChanged(
        address indexed user, uint256 indexed poolId, uint256 indexed stakeId, bool autoCompounding
    );
    event StakeTransferred(
        address indexed from, address indexed to, uint256 indexed poolId, uint256 stakeId
    );
    event RewardsPaidIn(uint256 amount);

    constructor(IERC20 _stakingToken, IERC20 _rewardsToken) Ownable() {
        stakingToken = _stakingToken;
        rewardsToken = _rewardsToken;
    }

    function addPool(uint256 lockPeriod) external onlyOwner {
        pools.push(
            Pool({
                lockPeriod: lockPeriod,
                accUNAIPerShare: 0,
                totalStaked: 0,
                lastRewardTime: block.timestamp
            })
        );
        emit PoolAdded(pools.length - 1, lockPeriod);
    }

    function updatePool(uint256 poolId) public {
        Pool storage pool = pools[poolId];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 tokenSupply = pool.totalStaked;
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 rewardAmount = rewardsToken.balanceOf(address(this));
        pool.accUNAIPerShare += rewardAmount * 1e18 / tokenSupply;
        pool.lastRewardTime = block.timestamp;
    }

    function stake(uint256 poolId, uint256 amount, bool autoCompounding) external nonReentrant {
        updatePool(poolId);

        uint256 lockEndTime = block.timestamp + pools[poolId].lockPeriod;

        stakes[msg.sender][poolId].push(
            Stake({
                amount: amount,
                rewardDebt: amount * pools[poolId].accUNAIPerShare / 1e18,
                autoCompounding: autoCompounding,
                owner: msg.sender,
                lockEndTime: lockEndTime
            })
        );

        stakingToken.transferFrom(msg.sender, address(this), amount);

        pools[poolId].totalStaked += amount;

        emit Staked(msg.sender, poolId, stakes[msg.sender][poolId].length - 1, amount);
    }

    function unstake(uint256 poolId, uint256 stakeId) external nonReentrant {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");
        require(block.timestamp >= userStake.lockEndTime, "Lock period not over");

        updatePool(poolId);

        uint256 pending =
            userStake.amount * pools[poolId].accUNAIPerShare / 1e18 - userStake.rewardDebt;

        if (pending > 0) {
            if (userStake.autoCompounding) {
                userStake.amount += pending;
                emit AutoCompounded(msg.sender, poolId, stakeId, pending);
            } else {
                rewardsToken.transfer(msg.sender, pending);
                emit RewardsClaimed(msg.sender, poolId, stakeId, pending);
            }
        }

        stakingToken.transfer(msg.sender, userStake.amount);

        pools[poolId].totalStaked -= userStake.amount;

        userStake.amount = 0;
        userStake.rewardDebt = 0;

        emit Unstaked(msg.sender, poolId, stakeId, userStake.amount);
    }

    function claimRewards(uint256 poolId, uint256 stakeId) external nonReentrant {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");

        updatePool(poolId);

        uint256 pending =
            userStake.amount * pools[poolId].accUNAIPerShare / 1e18 - userStake.rewardDebt;

        if (pending > 0) {
            rewardsToken.transfer(msg.sender, pending);
            emit RewardsClaimed(msg.sender, poolId, stakeId, pending);
        }

        userStake.rewardDebt = userStake.amount * pools[poolId].accUNAIPerShare / 1e18;
    }

    function autoCompound(uint256 poolId, uint256 stakeId) external nonReentrant {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");

        updatePool(poolId);

        uint256 pending =
            userStake.amount * pools[poolId].accUNAIPerShare / 1e18 - userStake.rewardDebt;

        if (pending > 0) {
            userStake.amount += pending;
            emit AutoCompounded(msg.sender, poolId, stakeId, pending);
        }

        userStake.rewardDebt = userStake.amount * pools[poolId].accUNAIPerShare / 1e18;
    }

    function changeAutoCompoundingStatus(uint256 poolId, uint256 stakeId, bool autoCompounding)
        external
        nonReentrant
    {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");

        updatePool(poolId);

        uint256 pending =
            userStake.amount * pools[poolId].accUNAIPerShare / 1e18 - userStake.rewardDebt;

        if (pending > 0) {
            rewardsToken.transfer(msg.sender, pending);
            emit RewardsClaimed(msg.sender, poolId, stakeId, pending);
        }

        userStake.autoCompounding = autoCompounding;
        userStake.rewardDebt = userStake.amount * pools[poolId].accUNAIPerShare / 1e18; // Update reward debt
        emit AutoCompoundingStatusChanged(msg.sender, poolId, stakeId, autoCompounding);
    }

    function approveStakeTransfer(address to, uint256 poolId, uint256 stakeId)
        external
        nonReentrant
    {
        Stake storage userStake = stakes[msg.sender][poolId][stakeId];
        require(userStake.owner == msg.sender, "Not the owner of this stake");
        stakeApprovals[msg.sender] = to;
    }

    function transferStake(address from, address to, uint256 poolId, uint256 stakeId)
        external
        nonReentrant
    {
        require(stakeApprovals[from] == msg.sender, "Not approved for transfer");
        Stake storage userStake = stakes[from][poolId][stakeId];
        require(userStake.owner == from, "Not the owner of this stake");

        stakes[to][poolId].push(userStake);
        stakes[from][poolId][stakeId] = stakes[from][poolId][stakes[from][poolId].length - 1];
        stakes[from][poolId].pop();

        emit StakeTransferred(from, to, poolId, stakeId);
    }

    function payRewards(uint256 amount) external nonReentrant {
        rewardsToken.transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < pools.length; i++) {
            updatePool(i);
        }

        emit RewardsPaidIn(amount);
    }

    function estimateAPY(uint256 poolId, uint256 observationPeriod)
        external
        view
        returns (uint256)
    {
        uint256 rewardsPerShare = pools[poolId].accUNAIPerShare;

        // Annualize the rewards per share
        uint256 annualizedRewardsPerShare = (rewardsPerShare * 365 days) / observationPeriod;

        // Calculate APY
        uint256 apy = (annualizedRewardsPerShare * 100) / 1e18;
        return apy;
    }
}
