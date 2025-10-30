// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenVesting
 * @dev A token vesting contract that locks tokens and releases them gradually over time
 */
contract TokenVesting is Ownable, ReentrancyGuard {
    IERC20 public token;
    
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 releasedAmount;
        bool revocable;
        bool revoked;
    }
    
    mapping(address => VestingSchedule) public vestingSchedules;
    
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    );
    
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary);
    
    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Token address cannot be zero");
        token = IERC20(_token);
    }
    
    /**
     * @dev Creates a vesting schedule for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @param totalAmount Total amount of tokens to vest
     * @param cliffDuration Duration in seconds before tokens start vesting
     * @param vestingDuration Total duration in seconds for the vesting period
     * @param revocable Whether the vesting can be revoked by owner
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0), "Beneficiary cannot be zero address");
        require(totalAmount > 0, "Amount must be greater than 0");
        require(vestingDuration > 0, "Vesting duration must be greater than 0");
        require(vestingSchedules[beneficiary].totalAmount == 0, "Vesting schedule already exists");
        require(token.balanceOf(address(this)) >= totalAmount, "Insufficient contract balance");
        
        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: totalAmount,
            startTime: block.timestamp,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            releasedAmount: 0,
            revocable: revocable,
            revoked: false
        });
        
        emit VestingScheduleCreated(
            beneficiary,
            totalAmount,
            block.timestamp,
            cliffDuration,
            vestingDuration
        );
    }
    
    /**
     * @dev Releases vested tokens to the beneficiary
     */
    function releaseTokens() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No vesting schedule found");
        require(!schedule.revoked, "Vesting has been revoked");
        
        uint256 vestedAmount = _calculateVestedAmount(msg.sender);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;
        
        require(releasableAmount > 0, "No tokens available for release");
        
        schedule.releasedAmount += releasableAmount;
        require(token.transfer(msg.sender, releasableAmount), "Token transfer failed");
        
        emit TokensReleased(msg.sender, releasableAmount);
    }
    
    /**
     * @dev Revokes the vesting schedule (only if revocable)
     * @param beneficiary Address of the beneficiary whose vesting to revoke
     */
    function revokeVesting(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule found");
        require(schedule.revocable, "Vesting is not revocable");
        require(!schedule.revoked, "Vesting already revoked");
        
        uint256 vestedAmount = _calculateVestedAmount(beneficiary);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;
        
        schedule.revoked = true;
        
        if (releasableAmount > 0) {
            schedule.releasedAmount += releasableAmount;
            require(token.transfer(beneficiary, releasableAmount), "Token transfer failed");
        }
        
        emit VestingRevoked(beneficiary);
    }
    
    /**
     * @dev Calculates the vested amount for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return The amount of tokens that have vested
     */
    function _calculateVestedAmount(address beneficiary) private view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }
        
        if (block.timestamp >= schedule.startTime + schedule.cliffDuration + schedule.vestingDuration) {
            return schedule.totalAmount;
        }
        
        uint256 timeFromStart = block.timestamp - schedule.startTime - schedule.cliffDuration;
        uint256 vestedAmount = (schedule.totalAmount * timeFromStart) / schedule.vestingDuration;
        
        return vestedAmount;
    }
    
    /**
     * @dev Returns the releasable amount for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return The amount of tokens that can be released
     */
    function getReleasableAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (schedule.revoked) {
            return 0;
        }
        uint256 vestedAmount = _calculateVestedAmount(beneficiary);
        return vestedAmount - schedule.releasedAmount;
    }
}
