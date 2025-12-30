// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Credits-USDC DEX
/// @notice A simple AMM DEX for swapping Credits tokens with USDC
/// @dev Handles different decimal tokens (Credits: 18, USDC: 6)
contract CreditsDex {
    /* ========== CUSTOM ERRORS ========== */
    error InitError();
    error TokenTransferError(address _token);
    error ZeroQuantityError();
    error SlippageError();
    error InsufficientLiquidityError(uint256 _liquidityAvailable);

    /* ========== STATE VARS ========== */

    IERC20 public creditToken;
    IERC20 public assetToken; // USDC

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    event TokenSwap(
        address indexed _user,
        uint256 _tradeDirection,
        uint256 _tokensSwapped,
        uint256 _tokensReceived
    );
    event LiquidityProvided(
        address indexed _user,
        uint256 _liquidityMinted,
        uint256 _creditTokenAdded,
        uint256 _assetTokenAdded
    );
    event LiquidityRemoved(
        address indexed _user,
        uint256 _liquidityAmount,
        uint256 _creditTokenAmount,
        uint256 _assetTokenAmount
    );

    /* ========== CONSTRUCTOR ========== */
    constructor(address _creditToken, address _assetToken) {
        creditToken = IERC20(_creditToken);
        assetToken = IERC20(_assetToken);
    }

    /// @notice Initializes liquidity in the DEX with specified amounts of each token
    /// @dev User should approve DEX contract as spender for both tokens before calling init
    /// @param creditTokenAmount Number of credit tokens to initialize with
    /// @param assetTokenAmount Number of asset tokens (USDC) to initialize with
    /// @return totalLiquidity The initial liquidity amount (uses credit token amount as base)
    function init(uint256 creditTokenAmount, uint256 assetTokenAmount) public returns (uint256) {
        if (totalLiquidity != 0) revert InitError();
        if (creditTokenAmount == 0 || assetTokenAmount == 0) revert ZeroQuantityError();

        // Use credit token amount as the liquidity base
        totalLiquidity = creditTokenAmount;
        liquidity[msg.sender] = creditTokenAmount;

        // Transfer credit tokens to the contract
        bool creditTokenTransferred = creditToken.transferFrom(
            msg.sender,
            address(this),
            creditTokenAmount
        );
        if (!creditTokenTransferred) revert TokenTransferError(address(creditToken));

        // Transfer asset tokens (USDC) to the contract
        bool assetTokenTransferred = assetToken.transferFrom(
            msg.sender,
            address(this),
            assetTokenAmount
        );
        if (!assetTokenTransferred) revert TokenTransferError(address(assetToken));

        emit LiquidityProvided(msg.sender, creditTokenAmount, creditTokenAmount, assetTokenAmount);

        return totalLiquidity;
    }

    /// @notice Returns yOutput for xInput using constant product formula with 0.3% fee
    /// @param xInput Amount of token X to be sold
    /// @param xReserves Amount of liquidity for token X
    /// @param yReserves Amount of liquidity for token Y
    /// @return yOutput Amount of token Y that can be purchased
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public pure returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput * 997;
        uint256 numerator = xInputWithFee * yReserves;
        uint256 denominator = (xReserves * 1000) + xInputWithFee;
        return numerator / denominator;
    }

    function getAssetAddr() external view returns (address) {
        return address(assetToken);
    }

    function getCreditAddr() external view returns (address) {
        return address(creditToken);
    }

    /// @notice Get credit reserves in the DEX
    function getCreditReserves() external view returns (uint256) {
        return creditToken.balanceOf(address(this));
    }

    /// @notice Get asset (USDC) reserves in the DEX
    function getAssetReserves() external view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    /// @notice Helper function to get assetOut from a specified creditIn
    /// @param creditIn Amount of credits to calculate assetToken price
    /// @return assetOut Amount of assets tradable for 'creditIn' amount of credits
    function creditInPrice(uint256 creditIn) external view returns (uint256 assetOut) {
        uint256 credReserves = creditToken.balanceOf(address(this));
        uint256 assetReserves = assetToken.balanceOf(address(this));
        return price(creditIn, credReserves, assetReserves);
    }

    /// @notice Helper function to get creditOut from a specified assetIn
    /// @param assetIn Amount of assets to calculate creditToken price
    /// @return creditOut Amount of credits tradable for 'assetIn' amount of assets
    function assetInPrice(uint256 assetIn) external view returns (uint256 creditOut) {
        uint256 assetReserves = assetToken.balanceOf(address(this));
        uint256 creditReserves = creditToken.balanceOf(address(this));
        return price(assetIn, assetReserves, creditReserves);
    }

    /// @notice Helper function to get assetIn required for a specified creditOut
    /// @param creditOut Amount of credit the user wishes to receive
    /// @return assetIn Amount of asset necessary to receive creditOut
    function creditOutPrice(uint256 creditOut) external view returns (uint256 assetIn) {
        uint256 assetReserves = assetToken.balanceOf(address(this));
        uint256 creditReserves = creditToken.balanceOf(address(this));

        if (creditOut >= creditReserves) revert InsufficientLiquidityError(creditReserves);

        uint256 numerator = assetReserves * creditOut * 1000;
        uint256 denominator = (creditReserves - creditOut) * 997;
        return (numerator / denominator) + 1;
    }

    /// @notice Helper function to get creditIn required for a specified assetOut
    /// @param assetOut Amount of asset the user wishes to receive
    /// @return creditIn Amount of credit necessary to receive assetOut
    function assetOutPrice(uint256 assetOut) external view returns (uint256 creditIn) {
        uint256 assetReserves = assetToken.balanceOf(address(this));
        uint256 creditReserves = creditToken.balanceOf(address(this));

        if (assetOut >= assetReserves) revert InsufficientLiquidityError(assetReserves);

        uint256 numerator = creditReserves * assetOut * 1000;
        uint256 denominator = (assetReserves - assetOut) * 997;
        return (numerator / denominator) + 1;
    }

    /// @notice Returns amount of liquidity provided by an address
    /// @param _user The address to check the liquidity of
    /// @return Amount of liquidity _user has provided
    function getLiquidity(address _user) public view returns (uint256) {
        return liquidity[_user];
    }

    /// @notice Trades creditTokens for assetTokens (USDC)
    /// @param tokensIn The number of credit tokens to be sold
    /// @param minTokensBack The minimum number of asset tokens to accept (slippage protection)
    /// @return tokenOutput The number of asset tokens received
    function creditToAsset(
        uint256 tokensIn,
        uint256 minTokensBack
    ) public returns (uint256 tokenOutput) {
        if (tokensIn == 0) revert ZeroQuantityError();
        uint256 creditTokenReserve = creditToken.balanceOf(address(this));
        uint256 assetTokenReserve = assetToken.balanceOf(address(this));

        tokenOutput = price(tokensIn, creditTokenReserve, assetTokenReserve);
        if (tokenOutput < minTokensBack) revert SlippageError();

        bool creditTokenTransferred = creditToken.transferFrom(
            msg.sender,
            address(this),
            tokensIn
        );
        if (!creditTokenTransferred) revert TokenTransferError(address(creditToken));

        bool assetTokenTransferred = assetToken.transfer(msg.sender, tokenOutput);
        if (!assetTokenTransferred) revert TokenTransferError(address(assetToken));

        emit TokenSwap(msg.sender, 0, tokensIn, tokenOutput);
    }

    /// @notice Trades assetTokens (USDC) for creditTokens
    /// @param tokensIn The number of asset tokens to be sold
    /// @param minTokensBack The minimum number of credit tokens to accept (slippage protection)
    /// @return tokenOutput The number of credit tokens received
    function assetToCredit(
        uint256 tokensIn,
        uint256 minTokensBack
    ) public returns (uint256 tokenOutput) {
        if (tokensIn == 0) revert ZeroQuantityError();
        uint256 assetTokenReserve = assetToken.balanceOf(address(this));
        uint256 creditTokenReserve = creditToken.balanceOf(address(this));

        tokenOutput = price(tokensIn, assetTokenReserve, creditTokenReserve);
        if (tokenOutput < minTokensBack) revert SlippageError();

        bool assetTokenTransferred = assetToken.transferFrom(
            msg.sender,
            address(this),
            tokensIn
        );
        if (!assetTokenTransferred) revert TokenTransferError(address(assetToken));

        bool creditTokenTransferred = creditToken.transfer(msg.sender, tokenOutput);
        if (!creditTokenTransferred) revert TokenTransferError(address(creditToken));

        emit TokenSwap(msg.sender, 1, tokensIn, tokenOutput);
    }

    /// @notice Allows user to provide liquidity to the DEX
    /// @param creditTokenDeposited The number of credit tokens to deposit
    /// @return liquidityMinted The amount of liquidity tokens minted
    function deposit(uint256 creditTokenDeposited) public returns (uint256 liquidityMinted) {
        if (creditTokenDeposited == 0) revert ZeroQuantityError();

        uint256 creditTokenReserve = creditToken.balanceOf(address(this));
        uint256 assetTokenReserve = assetToken.balanceOf(address(this));
        
        // Calculate required asset tokens to maintain ratio
        uint256 assetTokenDeposited = (creditTokenDeposited * assetTokenReserve) / creditTokenReserve;

        liquidityMinted = (creditTokenDeposited * totalLiquidity) / creditTokenReserve;

        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        bool creditTokenTransferred = creditToken.transferFrom(
            msg.sender,
            address(this),
            creditTokenDeposited
        );
        if (!creditTokenTransferred) revert TokenTransferError(address(creditToken));

        bool assetTokenTransferred = assetToken.transferFrom(
            msg.sender,
            address(this),
            assetTokenDeposited
        );
        if (!assetTokenTransferred) revert TokenTransferError(address(assetToken));

        emit LiquidityProvided(
            msg.sender,
            liquidityMinted,
            creditTokenDeposited,
            assetTokenDeposited
        );
    }

    /// @notice Allows users to withdraw liquidity
    /// @param amount The amount of liquidity to withdraw
    /// @return creditTokenAmount The number of credit tokens received
    /// @return assetTokenAmount The number of asset tokens received
    function withdraw(
        uint256 amount
    ) public returns (uint256 creditTokenAmount, uint256 assetTokenAmount) {
        if (liquidity[msg.sender] < amount)
            revert InsufficientLiquidityError(liquidity[msg.sender]);

        uint256 creditTokenReserve = creditToken.balanceOf(address(this));
        uint256 assetTokenReserve = assetToken.balanceOf(address(this));

        creditTokenAmount = (amount * creditTokenReserve) / totalLiquidity;
        assetTokenAmount = (amount * assetTokenReserve) / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        bool creditTokenSent = creditToken.transfer(msg.sender, creditTokenAmount);
        if (!creditTokenSent) revert TokenTransferError(address(creditToken));
        
        bool assetTokenSent = assetToken.transfer(msg.sender, assetTokenAmount);
        if (!assetTokenSent) revert TokenTransferError(address(assetToken));

        emit LiquidityRemoved(msg.sender, amount, creditTokenAmount, assetTokenAmount);
    }
}

