// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/ISemver.sol";

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)
/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title ERC20 escrow contract
/// @notice receives L2 ERC20 tokens and allow withdrawal after lock period.
///        Allows specified only recipient to withdraw.
contract ERC20Escrow is ISemver {
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice  current lock index
    uint public currentIdx;

    /// @notice Lock records how tokens are locked
    struct Lock {
        uint lockIdx;
        uint amount;
        uint lockPeriod;
        address sender;
        address receiver;
        address token;
        LockStatus lockStatus;
    }

    /// @notice lock could have any of this status
    enum LockStatus {
        Locked,
        Unlocked,
        Withdrawn
    }

    /// @notice map(sender, reciever, lockIdx) -> Lock
    mapping (address => mapping(address => mapping(uint => Lock))) locks;


    /// @notice Emitted when contract is initialized
    event Initialized();

    /// @notice Emitted when token is locked
    event LockedToken(
        uint indexed lockIdx,
        address sender,
        address receiver,
        address token,
        uint amount,
        uint lockPeriod
    );

    /// @notice Emitted when token is unlocked
    event UnlockedToken(
        uint indexed lockIdx,
        address sender,
        address receiver,
        address token
    );

    /// @notice Emitted when token is withdrawn
    event WithdrawToken(
        uint indexed lockIdx,
        address sender,
        address receiver,
        address token,
        uint amount
    );


    /// @notice Constructs the ERC20Escrow contract.
    constructor() {
        currentIdx = 0;
        emit Initialized();
    }

    /// @notice Specify lock parameters and locks token
    /// @dev Assumes contract has allowance before function call
    /// @param _lockPeriod lock period
    /// @param _receiver lock receiver
    /// @param _token locked token address
    /// @param _amount lock token amount
    function lockToken(uint _lockPeriod, address _receiver, address _token, uint _amount) external {
        require(_lockPeriod > 0, "ERC20Escrow::lockToken::Lock period must be at least one block");

        Lock memory lock = Lock ({
            lockIdx: currentIdx,
            amount: _amount,
            lockPeriod: block.number + _lockPeriod,
            sender: msg.sender,
            receiver: _receiver,
            token: _token,
            lockStatus: LockStatus.Locked
        });

        locks[msg.sender][_receiver][currentIdx] = lock;

        currentIdx +=1;

        // receive token
        IERC20 token = IERC20(lock.token);
        token.transferFrom(msg.sender, address(this), lock.amount);

        emit LockedToken(
            lock.lockIdx,
            lock.sender,
            lock.receiver,
            lock.token,
            lock.amount,
            lock.lockPeriod
        );
    }

    /// @notice Unlocks a lock
    /// @dev Must be called once and before withdraw function
    /// @param _receiver lock receiver
    /// @param _lockIdx locked token address
    function unlockToken(address _receiver, uint _lockIdx) external {
        Lock memory lock = locks[msg.sender][_receiver][_lockIdx];

        require(lock.lockStatus != LockStatus.Unlocked, "ERC20Escrow::unlockToken::Already unlocked");
        require(lock.lockStatus != LockStatus.Withdrawn, "ERC20Escrow::unlockToken::Token already withdhrawn");

        require(lock.sender == msg.sender, "ERC20Escrow::unlockToken::Sender does not match lock");
        require(lock.receiver == _receiver, "ERC20Escrow::unlockToken::Receiver does not match lock");
        require(lock.lockIdx == _lockIdx, "ERC20Escrow::unlockToken::Lock index does not match lock");

        require(block.number >= lock.lockPeriod, "ERC20Escrow::unlockToken::Lock period not over");

        lock.lockStatus = LockStatus.Unlocked;
        locks[msg.sender][_receiver][currentIdx] = lock;

        emit UnlockedToken(
            lock.lockIdx,
            lock.sender,
            lock.receiver,
            lock.token
        );
    }

    /// @notice Withdraw token from lock
    /// @param _sender lock receiver
    /// @param _receiver locked token address
    /// @param _lockIdx locked token address
    function withdrawToken(address _sender, address _receiver, uint _lockIdx) external {
        Lock memory lock = locks[_sender][_receiver][_lockIdx];

        require(lock.lockStatus != LockStatus.Unlocked, "ERC20Escrow::withdrawToken::Token is locked");
        require(lock.lockStatus != LockStatus.Withdrawn, "ERC20Escrow::withdrawToken::Token already withdhrawn");

        lock.lockStatus = LockStatus.Withdrawn;

        // transfer token
        IERC20 token = IERC20(lock.token);
        token.transfer(_receiver, lock.amount);

        emit WithdrawToken(
            lock.lockIdx,
            lock.sender,
            lock.receiver,
            lock.token,
            lock.amount
        );
    }
}
