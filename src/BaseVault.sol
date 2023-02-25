// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {Math512Bits} from "joe-v2/libraries/Math512Bits.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCast} from "joe-v2/libraries/SafeCast.sol";

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IBaseVault} from "./interfaces/IBaseVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {IWNative} from "./interfaces/IWNative.sol";

/**
 * @title Liquidity Book Base Vault contract
 * @author Trader Joe
 * @notice This contract is used to interact with the Liquidity Book Pair contract. It should be inherited by a Vault
 * contract that defines the `_previewShares` function to calculate the amount of shares to mint.
 * The immutable data should be encoded as follows:
 * - 0x00: 20 bytes: The address of the LB pair.
 * - 0x14: 20 bytes: The address of the token X.
 * - 0x28: 20 bytes: The address of the token Y.
 * - 0x3C: 1 bytes: The decimals of the token X.
 * - 0x3D: 1 bytes: The decimals of the token Y.
 */
abstract contract BaseVault is Clone, ERC20Upgradeable, ReentrancyGuardUpgradeable, IBaseVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Math512Bits for uint256;
    using SafeCast for uint256;

    uint8 internal constant _SHARES_DECIMALS = 6;
    uint256 internal constant _SHARES_PRECISION = 10 ** _SHARES_DECIMALS;

    IVaultFactory private immutable _factory;
    address private immutable _wnative;

    IStrategy private _strategy;
    bool private _depositsPaused;

    QueuedWithdrawal[] private _queuedWithdrawalsByRound;

    uint128 private _totalAmountX;
    uint128 private _totalAmountY;

    /**
     * @dev Modifier to check if the caller is the factory.
     */
    modifier onlyFactory() {
        if (msg.sender != address(_factory)) revert BaseVault__OnlyFactory();
        _;
    }

    /**
     * @dev Modifier to check if the deposits are not paused.
     */
    modifier whenDepositsNotPaused() {
        if (_depositsPaused) revert BaseVault__DepositsPaused();
        _;
    }

    /**
     * @dev Modifier to check if one of the two vault tokens is the wrapped native token.
     */
    modifier onlyVaultWithNativeToken() {
        if (address(_tokenX()) != _wnative && address(_tokenY()) != _wnative) revert BaseVault__NoNativeToken();
        _;
    }

    /**
     * @dev Modifier to check if the recipient is not the address(0)
     */
    modifier onlyValidRecipient(address recipient) {
        if (recipient == address(0)) revert BaseVault__InvalidRecipient();
        _;
    }

    /**
     * @dev Modifier to check that the amount of shares is greater than zero.
     */
    modifier NonZeroShares(uint256 shares) {
        if (shares == 0) revert BaseVault__ZeroShares();
        _;
    }

    /**
     * @dev Constructor of the contract.
     * @param factory Address of the factory.
     */
    constructor(IVaultFactory factory) {
        _factory = factory;
        _wnative = factory.getWNative();
    }

    /**
     * @dev Receive function. Mainly added to silence the compiler warning.
     * Highly unlikely to be used as the base vault needs at least 62 bytes of immutable data added to the payload
     * (3 addresses and 2 bytes of lenths), so this function should never be called.
     */
    receive() external payable {
        if (msg.sender != _wnative) revert BaseVault__OnlyWNative();
    }

    /**
     * @notice Allows the contract to receive native tokens from the WNative contract.
     * @dev We can't use the `receive` function because the immutable clone library adds calldata to the payload
     * that are taken as a function signature and parameters.
     */
    fallback() external payable {
        if (msg.sender != _wnative) revert BaseVault__OnlyWNative();
    }

    /**
     * @dev Initializes the contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function initialize(string memory name, string memory symbol) public virtual override initializer {
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();

        // Initialize the first round of queued withdrawals.
        _queuedWithdrawalsByRound.push();
    }

    /**
     * @notice Returns the decimals of the vault token.
     * @return The decimals of the vault token.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimalsY() + _SHARES_DECIMALS;
    }

    /**
     * @dev Returns the address of the factory.
     * @return The address of the factory.
     */
    function getFactory() public view virtual override returns (IVaultFactory) {
        return _factory;
    }

    /**
     * @dev Returns the address of the pair.
     * @return The address of the pair.
     */
    function getPair() public pure virtual override returns (ILBPair) {
        return _pair();
    }

    /**
     * @dev Returns the address of the token X.
     * @return The address of the token X.
     */
    function getTokenX() public pure virtual override returns (IERC20Upgradeable) {
        return _tokenX();
    }

    /**
     * @dev Returns the address of the token Y.
     * @return The address of the token Y.
     */
    function getTokenY() public pure virtual override returns (IERC20Upgradeable) {
        return _tokenY();
    }

    /**
     * @dev Returns the address of the current strategy.
     * @return The address of the strategy
     */
    function getStrategy() public view virtual override returns (IStrategy) {
        return _strategy;
    }

    /**
     * @dev Returns the AUM annual fee of the strategy.
     * @return
     */
    function getAumAnnualFee() public view virtual override returns (uint256) {
        IStrategy strategy = _strategy;

        return address(strategy) == address(0) ? 0 : strategy.getAumAnnualFee();
    }

    /**
     * @dev Returns the range of the strategy.
     * @return low The lower bound of the range.
     * @return upper The upper bound of the range.
     */
    function getRange() public view virtual override returns (uint24 low, uint24 upper) {
        IStrategy strategy = _strategy;

        return address(strategy) == address(0) ? (0, 0) : strategy.getRange();
    }

    /**
     * @dev Returns operators of the strategy.
     * @return defaultOperator The default operator.
     * @return operator The operator.
     */
    function getOperators() public view virtual override returns (address defaultOperator, address operator) {
        IStrategy strategy = _strategy;

        defaultOperator = _factory.getDefaultOperator();
        operator = address(strategy) == address(0) ? address(0) : strategy.getOperator();
    }

    /**
     * @dev Returns the total balances of the pair.
     * @return amountX The total balance of token X.
     * @return amountY The total balance of token Y.
     */
    function getBalances() public view virtual override returns (uint256 amountX, uint256 amountY) {
        (amountX, amountY) = _getBalances(_strategy);
    }

    /**
     * @dev Returns the pending fees of the strategy.
     * @return feesX The pending fees of token X.
     * @return feesY The pending fees of token Y.
     */
    function getPendingFees() public view virtual override returns (uint256 feesX, uint256 feesY) {
        IStrategy strategy = _strategy;

        return address(strategy) == address(0) ? (0, 0) : strategy.getPendingFees();
    }

    /**
     * @dev Preview the amount of shares to be minted.
     * @param amountX The amount of token X to be deposited.
     * @param amountY The amount of token Y to be deposited.
     * @return shares The amount of shares to be minted.
     * @return effectiveX The effective amount of token X to be deposited.
     * @return effectiveY The effective amount of token Y to be deposited.
     */
    function previewShares(uint256 amountX, uint256 amountY)
        public
        view
        virtual
        override
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        return _previewShares(_strategy, amountX, amountY);
    }

    /**
     * @dev Preview the amount of tokens to be redeemed on withdrawal.
     * @param shares The amount of shares to be redeemed.
     * @return amountX The amount of token X to be redeemed.
     * @return amountY The amount of token Y to be redeemed.
     */
    function previewAmounts(uint256 shares) public view virtual override returns (uint256 amountX, uint256 amountY) {
        return _previewAmounts(_strategy, shares, totalSupply());
    }

    /**
     * @notice Returns if the deposits are paused.
     * @return paused True if the deposits are paused.
     */
    function isDepositsPaused() public view virtual override returns (bool paused) {
        return _depositsPaused;
    }

    /**
     * @notice Returns the current round of queued withdrawals.
     * @return round The current round of queued withdrawals.
     */
    function getCurrentRound() public view virtual override returns (uint256 round) {
        return _queuedWithdrawalsByRound.length - 1;
    }

    /**
     * @notice Returns the queued withdrawal of the round for an user.
     * @param round The round.
     * @param user The user.
     * @return shares The amount of shares that are queued for withdrawal.
     */
    function getQueuedWithdrawal(uint256 round, address user) public view virtual override returns (uint256 shares) {
        return _queuedWithdrawalsByRound[round].userWithdrawals[user];
    }

    /**
     * @notice Returns the total shares that were queued for the round.
     * @param round The round.
     * @return totalQueuedShares The total shares that were queued for the round.
     */
    function getTotalQueuedWithdrawal(uint256 round) public view virtual override returns (uint256 totalQueuedShares) {
        return _queuedWithdrawalsByRound[round].totalQueuedShares;
    }

    /**
     * @notice Returns the total shares that were queued for the current round.
     * @return totalQueuedShares The total shares that were queued for the current round.
     */
    function getCurrentTotalQueuedWithdrawal() public view virtual override returns (uint256 totalQueuedShares) {
        return _queuedWithdrawalsByRound[_queuedWithdrawalsByRound.length - 1].totalQueuedShares;
    }

    /**
     * @notice Returns the amounts that can be redeemed for an user on the round.
     * @param round The round.
     * @param user The user.
     * @return amountX The amount of token X that can be redeemed.
     * @return amountY The amount of token Y that can be redeemed.
     */
    function getRedeemableAmounts(uint256 round, address user)
        public
        view
        virtual
        override
        returns (uint256 amountX, uint256 amountY)
    {
        // Get the queued withdrawal of the round.
        QueuedWithdrawal storage queuedWithdrawal = _queuedWithdrawalsByRound[round];

        // Get the total amount of tokens that were queued for the round.
        uint256 totalAmountX = queuedWithdrawal.totalAmountX;
        uint256 totalAmountY = queuedWithdrawal.totalAmountY;

        // Get the shares that were queued for the user and the total of shares.
        uint256 shares = queuedWithdrawal.userWithdrawals[user];
        uint256 totalShares = queuedWithdrawal.totalQueuedShares;

        // Calculate the amounts to be redeemed.
        if (totalShares > 0) {
            amountX = totalAmountX * shares / totalShares;
            amountY = totalAmountY * shares / totalShares;
        }
    }

    /**
     * @dev Deposits tokens to the strategy.
     * @param amountX The amount of token X to be deposited.
     * @param amountY The amount of token Y to be deposited.
     * @return shares The amount of shares to be minted.
     * @return effectiveX The effective amount of token X to be deposited.
     * @return effectiveY The effective amount of token Y to be deposited.
     */
    function deposit(uint256 amountX, uint256 amountY)
        public
        virtual
        override
        nonReentrant
        whenDepositsNotPaused
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        // Calculate the shares and effective amounts, also returns the strategy to save gas.
        IStrategy strategy;
        (strategy, shares, effectiveX, effectiveY) = _deposit(amountX, amountY);

        // Transfer the tokens to the strategy
        if (effectiveX > 0) _tokenX().safeTransferFrom(msg.sender, address(strategy), effectiveX);
        if (effectiveY > 0) _tokenY().safeTransferFrom(msg.sender, address(strategy), effectiveY);
    }

    /**
     * @dev Deposits native tokens and send the tokens to the strategy.
     * @param amountX The amount of token X to be deposited.
     * @param amountY The amount of token Y to be deposited.
     * @return shares The amount of shares to be minted.
     * @return effectiveX The effective amount of token X to be deposited.
     * @return effectiveY The effective amount of token Y to be deposited.
     */
    function depositNative(uint256 amountX, uint256 amountY)
        public
        payable
        virtual
        override
        nonReentrant
        whenDepositsNotPaused
        onlyVaultWithNativeToken
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        (IERC20Upgradeable tokenX, IERC20Upgradeable tokenY) = (_tokenX(), _tokenY());

        address wnative = _wnative;
        bool isNativeX = address(tokenX) == wnative;

        // Check that the native token amount matches the amount of native tokens sent.
        if (isNativeX && amountX != msg.value || !isNativeX && amountY != msg.value) {
            revert BaseVault__InvalidNativeAmount();
        }

        // Calculate the shares and effective amounts
        IStrategy strategy;
        (strategy, shares, effectiveX, effectiveY) = _deposit(amountX, amountY);

        // Calculate the effective native amount and transfer the other token to the strategy.
        uint256 effectiveNative;
        if (isNativeX) {
            // Transfer the token Y to the strategy and cache the native amount.
            effectiveNative = effectiveX;
            if (effectiveY > 0) tokenY.safeTransferFrom(msg.sender, address(strategy), effectiveY);
        } else {
            // Transfer the token X to the strategy and cache the native amount.
            if (effectiveX > 0) tokenX.safeTransferFrom(msg.sender, address(strategy), effectiveX);
            effectiveNative = effectiveY;
        }

        // Deposit and send wnative to the strategy.
        if (effectiveNative > 0) {
            IWNative(wnative).deposit{value: effectiveNative}();
            IERC20Upgradeable(wnative).safeTransfer(address(strategy), effectiveNative);
        }

        // Refund dust native tokens, if any.
        if (msg.value > effectiveNative) {
            unchecked {
                _transferNative(msg.sender, msg.value - effectiveNative);
            }
        }
    }

    /**
     * @notice Queues withdrawal for `recipient`. The withdrawal will be effective after the next
     * rebalance. The user can withdraw the tokens after the rebalance, this allows users to withdraw
     * from LB positions without having to pay the gas price.
     * @param shares The shares to be queued for withdrawal.
     * @param recipient The address that will receive the withdrawn tokens after the rebalance.
     * @return round The round of the withdrawal.
     */
    function queueWithdrawal(uint256 shares, address recipient)
        public
        virtual
        override
        nonReentrant
        onlyValidRecipient(recipient)
        NonZeroShares(shares)
        returns (uint256 round)
    {
        // Check that the strategy is set.
        address strategy = address(_strategy);
        if (strategy == address(0)) revert BaseVault__InvalidStrategy();

        // Transfer the shares to the strategy, will revert if the user does not have enough shares.
        _transfer(msg.sender, strategy, shares);

        // Get the current round and the queued withdrawals for the round.
        round = _queuedWithdrawalsByRound.length - 1;
        QueuedWithdrawal storage queuedWithdrawals = _queuedWithdrawalsByRound[round];

        // Updates the total queued shares and the shares for the user.
        queuedWithdrawals.totalQueuedShares += shares;
        unchecked {
            // Can't overflow as the user can't have more shares than the total.
            queuedWithdrawals.userWithdrawals[recipient] += shares;
        }

        emit WithdrawalQueued(msg.sender, recipient, round, shares);
    }

    /**
     * @notice Cancels a queued withdrawal of `shares` for `recipient`. Cancelling a withdrawal is
     * only possible before the next rebalance. The user can cancel the withdrawal if they want to
     * stay in the vault. They will receive the vault shares back.
     * @param shares The shares to be cancelled for withdrawal.
     * @param recipient The address that will receive the withdrawn tokens after the rebalance.
     * @return round The round of the withdrawal that was cancelled.
     */
    function cancelQueuedWithdrawal(uint256 shares, address recipient)
        public
        virtual
        override
        nonReentrant
        onlyValidRecipient(recipient)
        NonZeroShares(shares)
        returns (uint256 round)
    {
        // Check that the strategy is set.
        address strategy = address(_strategy);
        if (strategy == address(0)) revert BaseVault__InvalidStrategy();

        // Get the current round and the queued withdrawals for the round.
        round = _queuedWithdrawalsByRound.length - 1;
        QueuedWithdrawal storage queuedWithdrawals = _queuedWithdrawalsByRound[round];

        // Check that the user has enough shares queued for withdrawal.
        uint256 maxShares = queuedWithdrawals.userWithdrawals[msg.sender];
        if (shares > maxShares) revert BaseVault__MaxSharesExceeded();

        // Updates the total queued shares and the shares for the user.
        unchecked {
            // Can't underflow as the user can't have more shares than the total, and its shares
            // were already checked.
            queuedWithdrawals.userWithdrawals[msg.sender] = maxShares - shares;
            queuedWithdrawals.totalQueuedShares -= shares;
        }

        // Transfer the shares back to the user.
        _transfer(strategy, msg.sender, shares);

        emit WithdrawalCancelled(msg.sender, msg.sender, round, shares);
    }

    /**
     * @notice Redeems a queued withdrawal for `recipient`. The user can redeem the tokens after the
     * rebalance. This can be easily check by comparing the current round with the round of the
     * withdrawal, if they're equal, the withdrawal is still pending.
     * @param recipient The address that will receive the withdrawn tokens after the rebalance.
     * @return amountX The amount of token X to be withdrawn.
     * @return amountY The amount of token Y to be withdrawn.
     */
    function redeemQueuedWithdrawal(uint256 round, address recipient)
        public
        virtual
        override
        nonReentrant
        onlyValidRecipient(recipient)
        returns (uint256 amountX, uint256 amountY)
    {
        // Get the amounts to be redeemed.
        (amountX, amountY) = _redeemWithdrawal(round, recipient);

        // Transfer the tokens to the recipient.
        if (amountX > 0) _tokenX().safeTransfer(recipient, amountX);
        if (amountY > 0) _tokenY().safeTransfer(recipient, amountY);
    }

    /**
     * @notice Redeems a queued withdrawal for `recipient`. The user can redeem the tokens after the
     * rebalance. This can be easily check by comparing the current round with the round of the
     * withdrawal, if they're equal, the withdrawal is still pending.
     * The wrapped native token will be unwrapped and sent to the recipient.
     * @param recipient The address that will receive the withdrawn tokens after the rebalance.
     * @return amountX The amount of token X to be withdrawn.
     * @return amountY The amount of token Y to be withdrawn.
     */
    function redeemQueuedWithdrawalNative(uint256 round, address recipient)
        public
        virtual
        override
        nonReentrant
        onlyVaultWithNativeToken
        onlyValidRecipient(recipient)
        returns (uint256 amountX, uint256 amountY)
    {
        // Get the amounts to be redeemed.
        (amountX, amountY) = _redeemWithdrawal(round, recipient);

        // Transfer the tokens to the recipient.
        if (amountX > 0) _transferTokenOrNative(_tokenX(), recipient, amountX);
        if (amountY > 0) _transferTokenOrNative(_tokenY(), recipient, amountY);
    }

    /**
     * @notice Emergency withdraws from the vault and sends the tokens to the sender according to its share.
     * If the user had queued withdrawals, they will be claimable using the `redeemQueuedWithdrawal` and
     * `redeemQueuedWithdrawalNative` functions as usual. This function is only for users that didn't queue
     * any withdrawals and still have shares in the vault.
     * @dev This will only work if the vault is in emergency mode.
     */
    function emergencyWithdraw() public virtual override nonReentrant {
        // Check that the vault is in emergency mode.
        if (address(_strategy) != address(0)) revert BaseVault__NotInEmergencyMode();

        // Get the amount of shares the user has. If the user has no shares, it will revert.
        uint256 shares = balanceOf(msg.sender);
        if (shares == 0) revert BaseVault__ZeroShares();

        // Get the balances of the vault and the total shares.
        // The balances of the vault will not contain the executed withdrawals.
        (uint256 balanceX, uint256 balanceY) = _getBalances(IStrategy(address(0)));
        uint256 totalShares = totalSupply();

        // Calculate the amounts to be withdrawn.
        uint256 amountX = balanceX * shares / totalShares;
        uint256 amountY = balanceY * shares / totalShares;

        // Burn the shares of the user.
        _burn(msg.sender, shares);

        // Transfer the tokens to the user.
        if (amountX > 0) _tokenX().safeTransfer(msg.sender, amountX);
        if (amountY > 0) _tokenY().safeTransfer(msg.sender, amountY);

        emit EmergencyWithdrawal(msg.sender, shares, amountX, amountY);
    }

    /**
     * @notice Executes the queued withdrawals for the current round. The strategy should call this
     * function after having sent the queued withdrawals to the vault.
     * This function will burn the shares of the users that queued withdrawals and will update the
     * total amount of tokens in the vault and increase the round.
     * @dev Only the strategy can call this function.
     */
    function executeQueuedWithdrawals() public virtual override nonReentrant {
        // Check that the caller is the strategy, it also checks that the strategy was set.
        address strategy = address(_strategy);
        if (strategy != msg.sender) revert BaseVault__OnlyStrategy();

        // Get the current round and the queued withdrawals for that round.
        uint256 round = _queuedWithdrawalsByRound.length - 1;
        QueuedWithdrawal storage queuedWithdrawals = _queuedWithdrawalsByRound[round];

        // Check that the round has queued withdrawals, if none, the function will stop.
        uint256 totalQueuedShares = queuedWithdrawals.totalQueuedShares;
        if (totalQueuedShares == 0) return;

        // Burn the shares of the users that queued withdrawals and update the queued withdrawals.
        _burn(strategy, totalQueuedShares);
        _queuedWithdrawalsByRound.push();

        // Cache the total amounts of tokens in the vault.
        uint256 totalAmountX = _totalAmountX;
        uint256 totalAmountY = _totalAmountY;

        // Get the amount of tokens received by the vault after executing the withdrawals.
        uint256 receivedX = _tokenX().balanceOf(address(this)) - totalAmountX;
        uint256 receivedY = _tokenY().balanceOf(address(this)) - totalAmountY;

        // Update the total amounts of tokens in the vault.
        _totalAmountX = (totalAmountX + receivedX).safe128();
        _totalAmountY = (totalAmountY + receivedY).safe128();

        // Update the total amounts of tokens in the queued withdrawals.
        queuedWithdrawals.totalAmountX = uint128(receivedX);
        queuedWithdrawals.totalAmountY = uint128(receivedY);

        emit WithdrawalExecuted(round, totalQueuedShares, receivedX, receivedY);
    }

    /**
     * @dev Sets the address of the strategy.
     * Will send all tokens to the new strategy.
     * @param newStrategy The address of the new strategy.
     */
    function setStrategy(IStrategy newStrategy) public virtual override onlyFactory nonReentrant {
        IStrategy currentStrategy = _strategy;

        // Verify that the strategy is not the same as the current strategy
        if (currentStrategy == newStrategy) revert BaseVault__SameStrategy();

        // Verify that the strategy is valid, i.e. it is for this vault and for the correct pair and tokens.
        if (
            newStrategy.getVault() != address(this) || newStrategy.getPair() != _pair()
                || newStrategy.getTokenX() != _tokenX() || newStrategy.getTokenY() != _tokenY()
        ) revert BaseVault__InvalidStrategy();

        // Check if there is a strategy currently set, if so, withdraw all tokens from it.
        if (address(currentStrategy) != address(0)) {
            IStrategy(currentStrategy).withdrawAll();
        }

        // Get the balances of the vault, this will not contain the executed withdrawals.
        (uint256 balanceX, uint256 balanceY) = _getBalances(IStrategy(address(0)));

        // Transfer all balances to the new strategy
        if (balanceX > 0) _tokenX().safeTransfer(address(newStrategy), balanceX);
        if (balanceY > 0) _tokenY().safeTransfer(address(newStrategy), balanceY);

        // Set the new strategy
        _setStrategy(newStrategy);
    }

    /**
     * @dev Pauses deposits.
     */
    function pauseDeposits() public virtual override onlyFactory nonReentrant {
        _depositsPaused = true;

        emit DepositsPaused();
    }

    /**
     * @dev Resumes deposits.
     */
    function resumeDeposits() public virtual override onlyFactory nonReentrant {
        _depositsPaused = false;

        emit DepositsResumed();
    }

    /**
     * @notice Sets the vault in emergency mode.
     * @dev This will pause deposits and withdraw all tokens from the strategy.
     */
    function setEmergencyMode() public virtual override onlyFactory nonReentrant {
        // Withdraw all tokens from the strategy.
        _strategy.withdrawAll();

        // Sets the strategy to the zero address, this will prevent any deposits.
        _setStrategy(IStrategy(address(0)));

        emit EmergencyMode();
    }

    /**
     * @dev Recovers ERC20 tokens sent to the vault.
     * @param token The address of the token to be recovered.
     * @param recipient The address of the recipient.
     * @param amount The amount of tokens to be recovered.
     */
    function recoverERC20(IERC20Upgradeable token, address recipient, uint256 amount)
        public
        virtual
        override
        nonReentrant
        onlyFactory
    {
        address strategy = address(_strategy);

        // Checks that the amount of token X to be recovered is not from any withdrawal. This will simply revert
        // if the vault is in emergency mode.
        if (token == _tokenX() && (strategy == address(0) || token.balanceOf(address(this)) < _totalAmountX + amount)) {
            revert BaseVault__InvalidToken();
        }

        // Checks that the amount of token Y to be recovered is not from any withdrawal. This will simply revert
        // if the vault is in emergency mode.
        if (token == _tokenY() && (strategy == address(0) || token.balanceOf(address(this)) < _totalAmountY + amount)) {
            revert BaseVault__InvalidToken();
        }

        if (token == this) {
            uint256 excessStrategy = balanceOf(strategy) - getCurrentTotalQueuedWithdrawal();

            // If the token is the vault's token, the remaining amount must be greater than the minimum shares.
            if (token == this && balanceOf(address(this)) + excessStrategy < amount + _SHARES_PRECISION) {
                revert BaseVault__BurnMinShares();
            }

            // Allow to recover vault tokens that were mistakenly sent to the strategy.
            if (excessStrategy > 0) {
                _transfer(strategy, address(this), excessStrategy);
            }
        }

        token.safeTransfer(recipient, amount);
    }

    /**
     * @dev Returns the address of the pair.
     * @return The address of the pair.
     */
    function _pair() internal pure virtual returns (ILBPair) {
        return ILBPair(_getArgAddress(0));
    }

    /**
     * @dev Returns the address of the token X.
     * @return The address of the token X.
     */
    function _tokenX() internal pure virtual returns (IERC20Upgradeable) {
        return IERC20Upgradeable(_getArgAddress(20));
    }

    /**
     * @dev Returns the address of the token Y.
     * @return The address of the token Y.
     */
    function _tokenY() internal pure virtual returns (IERC20Upgradeable) {
        return IERC20Upgradeable(_getArgAddress(40));
    }

    /**
     * @dev Returns the decimals of the token X.
     * @return decimalsX The decimals of the token X.
     */
    function _decimalsX() internal pure virtual returns (uint8 decimalsX) {
        return _getArgUint8(60);
    }

    /**
     * @dev Returns the decimals of the token Y.
     * @return decimalsY The decimals of the token Y.
     */
    function _decimalsY() internal pure virtual returns (uint8 decimalsY) {
        return _getArgUint8(61);
    }

    /**
     * @dev Returns shares and amounts of token X and token Y to be deposited.
     * @param strategy The address of the strategy.
     * @param amountX The amount of token X to be deposited.
     * @param amountY The amount of token Y to be deposited.
     * @return shares The amount of shares to be minted.
     * @return effectiveX The amount of token X to be deposited.
     * @return effectiveY The amount of token Y to be deposited.
     */
    function _previewShares(IStrategy strategy, uint256 amountX, uint256 amountY)
        internal
        view
        virtual
        returns (uint256 shares, uint256, uint256);

    /**
     * @dev Returns amounts of token X and token Y to be withdrawn.
     * @param strategy The address of the strategy.
     * @param shares The amount of shares to be withdrawn.
     * @param totalShares The total amount of shares.
     * @return amountX The amount of token X to be withdrawn.
     * @return amountY The amount of token Y to be withdrawn.
     */
    function _previewAmounts(IStrategy strategy, uint256 shares, uint256 totalShares)
        internal
        view
        virtual
        returns (uint256 amountX, uint256 amountY)
    {
        if (shares == 0) return (0, 0);

        if (shares > totalShares) revert BaseVault__InvalidShares();

        // Get the total amount of tokens held in the strategy
        (uint256 totalX, uint256 totalY) = _getBalances(strategy);

        // Calculate the amount of tokens to be withdrawn, pro rata to the amount of shares
        amountX = totalX.mulDivRoundDown(shares, totalShares);
        amountY = totalY.mulDivRoundDown(shares, totalShares);
    }

    /**
     * @dev Returns the total amount of tokens held in the strategy. This includes the balance, the amounts deposited in
     * LB and the unclaiemd and redeemed fees.
     * Will return the balance of the vault if no strategy is set.
     * @param strategy The address of the strategy.
     * @return amountX The amount of token X held in the strategy.
     * @return amountY The amount of token Y held in the strategy.
     */
    function _getBalances(IStrategy strategy) internal view virtual returns (uint256 amountX, uint256 amountY) {
        return address(strategy) == address(0)
            ? (_tokenX().balanceOf(address(this)) - _totalAmountX, _tokenY().balanceOf(address(this)) - _totalAmountY)
            : strategy.getBalances();
    }

    /**
     * @dev Sets the address of the strategy.
     * @param strategy The address of the strategy.
     */
    function _setStrategy(IStrategy strategy) internal virtual {
        _strategy = strategy;

        emit StrategySet(strategy);
    }

    /**
     * @dev Calculate the effective amounts to take from the user and mint the shares.
     * Will not transfer the tokens from the user.
     * @param amountX The amount of token X to be deposited.
     * @param amountY The amount of token Y to be deposited.
     * @return strategy The address of the strategy.
     * @return shares The amount of shares to be minted.
     * @return effectiveX The amount of token X to be deposited.
     * @return effectiveY The amount of token Y to be deposited.
     */
    function _deposit(uint256 amountX, uint256 amountY)
        internal
        virtual
        returns (IStrategy strategy, uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        // Check that at least one token is being deposited
        if (amountX == 0 && amountY == 0) revert BaseVault__ZeroAmount();

        // Verify that the strategy is set
        strategy = _strategy;
        if (address(strategy) == address(0)) revert BaseVault__InvalidStrategy();

        // Calculate the effective amounts to take from the user and the amount of shares to mint
        (shares, effectiveX, effectiveY) = _previewShares(strategy, amountX, amountY);

        if (shares == 0) revert BaseVault__ZeroShares();

        if (totalSupply() == 0) {
            // Avoid exploit when very little shares, min of total shares will always be _SHARES_PRECISION (1e6)
            shares -= _SHARES_PRECISION;
            _mint(address(this), _SHARES_PRECISION);
        }

        // Mint the shares
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, effectiveX, effectiveY, shares);
    }

    /**
     * @dev Redeems the queued withdrawal for a given round and a given user.
     * Does not transfer the tokens to the user.
     * @param user The address of the user.
     * @return amountX The amount of token X to be withdrawn.
     * @return amountY The amount of token Y to be withdrawn.
     */
    function _redeemWithdrawal(uint256 round, address user) internal returns (uint256 amountX, uint256 amountY) {
        QueuedWithdrawal storage queuedWithdrawals = _queuedWithdrawalsByRound[round];

        // Get the amount of shares to redeem, will revert if the user has no queued withdrawal
        uint256 shares = queuedWithdrawals.userWithdrawals[user];
        if (shares == 0) revert BaseVault__NoQueuedWithdrawal();

        // Calculate the amount of tokens to be withdrawn, pro rata to the amount of shares
        uint256 totalQueuedShares = queuedWithdrawals.totalQueuedShares;
        queuedWithdrawals.userWithdrawals[user] = 0;

        amountX = uint256(queuedWithdrawals.totalAmountX) * shares / totalQueuedShares;
        amountY = uint256(queuedWithdrawals.totalAmountY) * shares / totalQueuedShares;

        // Update the total amount of shares queued for withdrawal
        if (amountX != 0) _totalAmountX -= amountX.safe128();
        if (amountY != 0) _totalAmountY -= amountY.safe128();

        emit WithdrawalRedeemed(msg.sender, user, round, shares, amountX, amountY);
    }

    /**
     * @dev Helper function to transfer tokens to the recipient. If the token is the wrapped native token, it will be
     * unwrapped first and then transferred as native tokens.
     * @param token The address of the token to be transferred.
     * @param recipient The address to receive the tokens.
     * @param amount The amount of tokens to be transferred.
     */
    function _transferTokenOrNative(IERC20Upgradeable token, address recipient, uint256 amount) internal {
        address wnative = _wnative;
        if (address(token) == wnative) {
            IWNative(wnative).withdraw(amount);
            _transferNative(recipient, amount);
        } else {
            token.safeTransfer(recipient, amount);
        }
    }

    /**
     * @dev Helper function to transfer native tokens to the recipient.
     * @param recipient The address to receive the tokens.
     * @param amount The amount of tokens to be transferred.
     */
    function _transferNative(address recipient, uint256 amount) internal virtual {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert BaseVault__NativeTransferFailed();
    }
}
