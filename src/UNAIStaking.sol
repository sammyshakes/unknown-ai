pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UNAIStaking is Ownable {
    IERC20 public token;

    struct Stake {
        uint256 amount;
        uint256 lockPeriod;
        uint256 startTime;
        address owner;
    }

    struct StakeTransfer {
        uint256 stakeId;
        address from;
        address to;
    }

    Stake[] public stakes;
    mapping(address => uint256[]) public userStakes;
    mapping(uint256 => StakeTransfer) public stakeTransfers;

    event Staked(uint256 indexed stakeId, address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(uint256 indexed stakeId, address indexed user, uint256 amount);
    event RewardsClaimed(uint256 indexed stakeId, address indexed user, uint256 reward);
    event StakeTransferred(uint256 indexed stakeId, address indexed from, address indexed to);

    constructor(IERC20 _token) {
        token = _token;
    }

    function stake(uint256 amount, uint256 lockPeriod) external {
        require(amount > 0, "Amount must be greater than zero");
        require(lockPeriod > 0, "Lock period must be greater than zero");

        uint256 stakeId = stakes.length;
        stakes.push(Stake(amount, lockPeriod, block.timestamp, msg.sender));
        userStakes[msg.sender].push(stakeId);

        token.transferFrom(msg.sender, address(this), amount);

        emit Staked(stakeId, msg.sender, amount, lockPeriod);
    }

    function unstake(uint256 stakeId) external {
        Stake storage stake = stakes[stakeId];
        require(stake.owner == msg.sender, "Not the owner of this stake");
        require(block.timestamp >= stake.startTime + stake.lockPeriod, "Lock period not yet expired");

        uint256 amount = stake.amount;
        stake.amount = 0; // Set the staked amount to 0 to mark as unstaked

        token.transfer(msg.sender, amount);

        emit Unstaked(stakeId, msg.sender, amount);
    }

    function claimRewards(uint256 stakeId) external {
        Stake storage stake = stakes[stakeId];
        require(stake.owner == msg.sender, "Not the owner of this stake");

        uint256 reward = calculateReward(stake);
        // Logic to transfer rewards to the user
        // For simplicity, assuming rewards are paid in the same token
        token.transfer(msg.sender, reward);

        emit RewardsClaimed(stakeId, msg.sender, reward);
    }

    function transferStake(uint256 stakeId, address to) external {
        Stake storage stake = stakes[stakeId];
        require(stake.owner == msg.sender, "Not the owner of this stake");

        stakeTransfers[stakeId] = StakeTransfer(stakeId, msg.sender, to);
        stake.owner = to;

        emit StakeTransferred(stakeId, msg.sender, to);
    }

    function calculateReward(Stake storage stake) internal view returns (uint256) {
        // Reward calculation logic based on the amount staked and the lock period
        uint256 reward = (block.timestamp - stake.startTime) * stake.amount / stake.lockPeriod;
        return reward;
    }

    // Additional helper functions and modifiers can be added as needed
}
