// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GoblinDistributor is Ownable, ReentrancyGuard {
    error GoblinDistributor__CallerNotKeeper();
    error GoblinDistributor__InsufficientFunds();
    error GoblinDistributor__ClaimingNotOver();
    error GoblinDistributor__ContractEmpty();
    error GoblinDistributor__CooldownPeriod();
    error GoblinDistributor__ArraysUnmatched();
    error GoblinDistributor__SizeIsZero();
    error GoblinDistributor__ClaimNotOpen();
    error GoblinDistributor__RewardsEmpty();
    error GoblinDistributor__Blacklisted();
    error GoblinDistributor_MaxRewardExceeded();
    error GoblinDistributor__ClaimOpen();

    IERC20 public usdc;

    mapping(address => uint256) public rewards;
    mapping(address => bool) public isKeeper;
    mapping(address => bool) public isBlacklisted;

    uint256 public constant COOLDOWN_PERIOD = 300;

    uint256 public immutable CLAIM_OPENS; // Set To Time of Mainnet Launch
    uint256 public immutable CLAIM_ENDS; // Add Duration of Claiming Period in Seconds to CLAIM_OPENS

    uint256 public totalClaimableRewards;
    uint256 public lastWinnerUpdate;

    event RewardsAdded(uint256 indexed amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event KeeperSet(address indexed keeper, bool isKeeper);
    event RewardsWithdrawn(uint256 indexed amount);
    event WinnersAdded(uint256 indexed timestamp, uint256 indexed addedRewards);

    /// @param _usdc Address of the USDC token
    /// @param _start Timestamp of when claiming opens
    /// @dev Claiming period ends 7 days after the set start date
    constructor(address _usdc, uint256 _start) {
        usdc = IERC20(_usdc);
        CLAIM_OPENS = _start;
        CLAIM_ENDS = _start + 7 days;
    }

    modifier isKeeperOrAbove() {
        if (msg.sender != owner() && !isKeeper[msg.sender]) {
            revert GoblinDistributor__CallerNotKeeper();
        }
        _;
    }

    /// @notice Grants a user abilities to manage the contract
    /// @param _keeper Address of the user to grant abilities to
    /// @param _isKeeper Whether the user should be granted or have their abilities revoked
    /// @dev Keepers should only be trusted users
    function setKeeper(address _keeper, bool _isKeeper) external onlyOwner {
        isKeeper[_keeper] = _isKeeper;
        emit KeeperSet(_keeper, _isKeeper);
    }

    /// @notice Revokes a users ability to claim rewards
    /// @param _user Address of the user to blacklist
    /// @param _isBlacklisted Whether the user should be blacklisted or have their blacklist revoked
    /// @dev Only to be used in the event of a user faking winning trades on Goblin Mode
    function setBlacklisted(address _user, bool _isBlacklisted) external isKeeperOrAbove {
        isBlacklisted[_user] = _isBlacklisted;
    }

    /// @notice Top up the contract with more rewards
    /// @param _amount Amount of USDC to top up the contract with
    /// @dev Must be called before claiming goes live, so users have sufficient funds to claim
    function topUpFunds(uint256 _amount) external isKeeperOrAbove {
        if (usdc.balanceOf(msg.sender) < _amount) revert GoblinDistributor__InsufficientFunds();
        usdc.transferFrom(msg.sender, address(this), _amount);
        emit RewardsAdded(_amount);
    }

    /// @notice Withdraws all funds from the contract after event finishes
    /// @param _token Address of the token to withdraw
    function withdrawAll(address _token) external onlyOwner {
        if (block.timestamp < CLAIM_ENDS) revert GoblinDistributor__ClaimingNotOver();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) revert GoblinDistributor__ContractEmpty();
        IERC20(_token).transfer(msg.sender, balance);
        emit RewardsWithdrawn(balance);
    }

    /// @notice Adds winners and the amount they have won to the contract
    /// @param _users Array of addresses of the winners
    /// @param _rewardTotalUsdc Array of the amount of USDC each winner has won
    /// @dev IMPORTANT: Reward values should be set to maximum of 1e9 (1000 USDC) by keeper
    function addWinners(address[] calldata _users, uint256[] calldata _rewardTotalUsdc) external isKeeperOrAbove {
        if (block.timestamp < lastWinnerUpdate + COOLDOWN_PERIOD) revert GoblinDistributor__CooldownPeriod();
        uint256 userLen = _users.length;
        if (userLen != _rewardTotalUsdc.length) revert GoblinDistributor__ArraysUnmatched();
        if (userLen == 0) revert GoblinDistributor__SizeIsZero();
        if (block.timestamp > CLAIM_OPENS) revert GoblinDistributor__ClaimOpen();

        lastWinnerUpdate = block.timestamp;
        uint256 addedRewards;

        for (uint256 i = 0; i < userLen;) {
            uint256 _reward = _rewardTotalUsdc[i];
            rewards[_users[i]] += _reward;
            addedRewards += _reward;
            unchecked {
                i += 1;
            }
        }

        totalClaimableRewards += addedRewards;

        emit WinnersAdded(block.timestamp, addedRewards);
    }

    /// @notice Claims rewards for the caller
    /// @dev Can only be called during the claiming period set at deployment
    function claimRewards() external nonReentrant {
        if (isBlacklisted[msg.sender]) revert GoblinDistributor__Blacklisted();
        if (block.timestamp < CLAIM_OPENS || block.timestamp > CLAIM_ENDS) revert GoblinDistributor__ClaimNotOpen();
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert GoblinDistributor__RewardsEmpty();
        if (usdc.balanceOf(address(this)) < reward) revert GoblinDistributor__InsufficientFunds();
        rewards[msg.sender] = 0;
        totalClaimableRewards -= reward;
        usdc.transfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    /// @notice Returns available rewards for the caller
    function getPendingRewards() external view returns (uint256) {
        return rewards[msg.sender];
    }

    /// @notice Returns whether claiming is life or not
    function getIsClaimingLive() external view returns (bool) {
        return block.timestamp >= CLAIM_OPENS && block.timestamp <= CLAIM_ENDS;
    }

    /// @notice Returns the amount of rewards held by the contract
    /// @dev Should always be >= totalClaimableRewards
    function getContractRewardBalance() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getTimeToClaim() public view returns (uint256) {
        return block.timestamp < CLAIM_OPENS ? CLAIM_OPENS - block.timestamp : 0;
    }
}
