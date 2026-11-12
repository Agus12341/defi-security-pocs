// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IComptroller {
    function getAllMarkets() external view returns (address[] memory);
    function markets(address) external view returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
    function oracle() external view returns (address);
    function enterMarkets(address[] calldata) external returns (uint256[] memory);
    function getAccountLiquidity(address) external view returns (uint256, uint256, uint256);
    function _setCollateralFactor(address cToken, uint256 newCollateralFactorMantissa) external returns (uint256);
    function admin() external view returns (address);
}

interface ICToken {
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function borrowBalanceStored(address) external view returns (uint256);
    function underlying() external view returns (address);
    function mint(uint256) external returns (uint256);
    function redeem(uint256) external returns (uint256);
    function redeemUnderlying(uint256) external returns (uint256);
    function borrow(uint256) external returns (uint256);
    function repayBorrow(uint256) external returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256);
    function accrueInterest() external returns (uint256);
}

interface ICEther {
    function mint() external payable;
    function redeem(uint256) external returns (uint256);
    function borrow(uint256) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
}

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}

/// @dev USDT on Ethereum omits a return value from approve.
interface IUSDT {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
}

interface ILatamStable {
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
    function mint(address to, uint256 amount) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function PAUSER_ROLE() external view returns (bytes32);
    function MINTER_ROLE() external view returns (bytes32);
    function enforceBlocklist() external view returns (bool);
    function setEnforceBlocklist(bool enabled) external;
    function blockUser(address account) external;
    function isBlocked(address account) external view returns (bool);
    function COMPLIANCE_ROLE() external view returns (bytes32);
}

interface IOracle {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
    function getConfig(address cToken)
        external
        view
        returns (uint8 underlyingAssetDecimals, address priceFeed, uint256 fixedPrice);
}

interface IAgg {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}
