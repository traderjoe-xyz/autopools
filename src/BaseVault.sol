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

    IVaultFactory private immutable _factory;
    address private immutable _wnative;

    IStrategy private _strategy;

    /**
     * @dev Modifier to check if the caller is the factory.
     */
    modifier onlyFactory() {
        if (msg.sender != address(_factory)) revert BaseVault__OnlyFactory();
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
     * @dev Initializes the contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function initialize(string memory name, string memory symbol) public virtual override initializer {
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();
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
     * @dev Returns the strategist fee.
     * @return strategistFee The strategist fee.
     */
    function getStrategistFee() public view virtual override returns (uint256 strategistFee) {
        IStrategy strategy = _strategy;

        return address(strategy) == address(0) ? 0 : strategy.getStrategistFee();
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
        return _previewAmounts(_strategy, shares);
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
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        // Calculate the shares and effective amounts
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
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        (IERC20Upgradeable tokenX, IERC20Upgradeable tokenY) = (_tokenX(), _tokenY());

        address wnative = _wnative;
        bool isNativeX = address(tokenX) == wnative;

        // Check that the native token is one of the tokens of the pair.
        if (!isNativeX && address(tokenY) != wnative) revert BaseVault__NoNativeToken();

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
            effectiveNative = effectiveX;
            if (effectiveY > 0) tokenY.safeTransferFrom(msg.sender, address(strategy), effectiveY);
        } else {
            if (effectiveX > 0) tokenX.safeTransferFrom(msg.sender, address(strategy), effectiveX);
            effectiveNative = effectiveY;
        }

        // Deposit and send wnative to the strategy.
        if (effectiveNative > 0) {
            IWNative(wnative).deposit{value: effectiveNative}();
            IWNative(wnative).transfer(address(strategy), effectiveNative);
        }

        // Refund dust native tokens, if any.
        if (msg.value > effectiveNative) {
            unchecked {
                (bool success,) = address(msg.sender).call{value: msg.value - effectiveNative}("");
                if (!success) revert BaseVault__NativeTransferFailed();
            }
        }
    }

    /**
     * @dev Withdraws tokens from the strategy.
     * @param shares The amount of shares to be redeemed.
     * @return amountX The amount of token X to be redeemed.
     * @return amountY The amount of token Y to be redeemed.
     */
    function withdraw(uint256 shares) public virtual override nonReentrant returns (uint256 amountX, uint256 amountY) {
        if (shares == 0) revert BaseVault__ZeroShares();

        IStrategy strategy = _strategy;
        uint256 totalShares = totalSupply();

        // Check if the strategy is set
        if (address(strategy) == address(0)) {
            (amountX, amountY) = _previewAmounts(strategy, shares);

            // Burn the shares
            _burn(msg.sender, shares);

            if (amountX > 0) _tokenX().safeTransfer(msg.sender, amountX);
            if (amountY > 0) _tokenY().safeTransfer(msg.sender, amountY);
        } else {
            // Burn the shares
            _burn(msg.sender, shares);

            // Withdraw the tokens from the strategy and send them to the user
            (amountX, amountY) = strategy.withdraw(shares, totalShares, msg.sender);
        }

        emit Withdrawn(msg.sender, amountX, amountY, shares);
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
        ) {
            revert BaseVault__InvalidStrategy();
        }

        // Check if there is a strategy currently set
        if (address(currentStrategy) == address(0)) {
            // Transfer all balances to the new strategy
            (uint256 balanceX, uint256 balanceY) = _getBalances(currentStrategy);

            if (balanceX > 0) _tokenX().safeTransfer(address(newStrategy), balanceX);
            if (balanceY > 0) _tokenY().safeTransfer(address(newStrategy), balanceY);
        } else {
            // Withdraw all tokens from the current strategy and send them to the new strategy
            IStrategy(currentStrategy).withdraw(1, 1, address(newStrategy));

            // Unapprove the current strategy
            _approveStrategy(currentStrategy, 0);
        }

        // Set the new strategy
        _setStrategy(newStrategy);

        // Approve the new strategy
        _approveStrategy(newStrategy, type(uint256).max);
    }

    /**
     * @dev Pauses the vault.
     * Will send all tokens to the vault.
     */
    function pauseVault() public virtual override nonReentrant onlyFactory {
        IStrategy strategy = _strategy;

        // Withdraw all tokens from the strategy and send them to the vault
        strategy.withdraw(1, 1, address(this));

        // Unapprove the strategy
        _approveStrategy(strategy, 0);

        // Remove the current strategy
        _setStrategy(IStrategy(address(0)));
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
        if (token == _tokenX() || token == _tokenY()) revert BaseVault__InvalidToken();

        // If the token is the vault's token, the remaining amount must be greater than the minimum shares.
        if (token == this && IERC20Upgradeable(token).balanceOf(address(this)) <= amount + 1e6) {
            revert BaseVault__BurnMinShares();
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
     * @return amountX The amount of token X to be withdrawn.
     * @return amountY The amount of token Y to be withdrawn.
     */
    function _previewAmounts(IStrategy strategy, uint256 shares)
        internal
        view
        virtual
        returns (uint256 amountX, uint256 amountY)
    {
        if (shares == 0) return (0, 0);

        uint256 totalShares = totalSupply();

        if (totalShares == 0 || shares > totalShares) revert BaseVault__InvalidShares();

        // Get the total amount of tokens held in the strategy
        (uint256 totalX, uint256 totalY) = _getBalances(strategy);

        // Calculate the amount of tokens to be withdrawn, pro rata to the amount of shares
        amountX = totalX.mulDivRoundDown(shares, totalShares);
        amountY = totalY.mulDivRoundDown(shares, totalShares);
    }

    /**
     * @dev Returns the total amount of tokens held in the strategy. This includes the balance, the amounts deposited in
     * LB and the unclaiemd and claimed fees.
     * Will return the balance of the vault if no strategy is set.
     * @param strategy The address of the strategy.
     * @return amountX The amount of token X held in the strategy.
     * @return amountY The amount of token Y held in the strategy.
     */
    function _getBalances(IStrategy strategy) internal view virtual returns (uint256 amountX, uint256 amountY) {
        return address(strategy) == address(0)
            ? (_tokenX().balanceOf(address(this)), _tokenY().balanceOf(address(this)))
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
     * @dev Approves the `strategy` to spend `amount` for each tokenX, tokenY and LB token.
     * @param strategy The address of the strategy.
     * @param amount The amount to be approved.
     */
    function _approveStrategy(IStrategy strategy, uint256 amount) internal virtual {
        _tokenX().approve(address(strategy), amount);
        _tokenY().approve(address(strategy), amount);
        ILBToken(address(_pair())).setApprovalForAll(address(strategy), amount > 0);
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
            // Avoid exploit when very little shares, min of total shares will always be 1e6
            shares -= 1e6;
            _mint(address(this), 1e6);
        }

        // Mint the shares
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, effectiveX, effectiveY, shares);
    }
}
