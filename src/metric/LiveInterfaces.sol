// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMetricOmmSwapCallback {
    function metricOmmSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

interface IMetricOmmModifyLiquidityCallback {
    function metricOmmModifyLiquidityCallback(uint256 amount0Delta, uint256 amount1Delta, bytes calldata data)
        external;
}

struct LiquidityDelta {
    int256[] binIdxs;
    uint256[] shares;
}

struct PoolImmutables {
    address factory;
    address token0;
    address token1;
    uint256 token0ScaleMultiplier;
    uint256 token1ScaleMultiplier;
    uint256 initialScaledToken0PerShareE18;
    uint256 initialScaledToken1PerShareE18;
    uint256 minimalOperationalLiquidity;
    address immutablePriceProvider;
    int256 lowestBin;
    int256 highestBin;
    address extension1;
    address extension2;
    address extension3;
    address extension4;
    address extension5;
    address extension6;
    address extension7;
    uint256 beforeAddLiquidityOrder;
    uint256 afterAddLiquidityOrder;
    uint256 beforeRemoveLiquidityOrder;
    uint256 afterRemoveLiquidityOrder;
    uint256 beforeSwapOrder;
    uint256 afterSwapOrder;
}

interface IMetricOmmPool {
    function getImmutables() external view returns (PoolImmutables memory);
    function getSellAndBuyPrices() external returns (uint128 sellPriceX64, uint128 buyPriceX64);
    function swap(
        address recipient,
        bool zeroForOne,
        int128 amountSpecified,
        uint128 priceLimitX64,
        bytes calldata callbackData,
        bytes calldata extensionData
    ) external returns (int128, int128);
    function addLiquidity(
        address owner,
        uint80 salt,
        LiquidityDelta calldata deltas,
        bytes calldata callbackData,
        bytes calldata extensionData
    ) external returns (uint256 amount0Added, uint256 amount1Added);
    function removeLiquidity(address owner, uint80 salt, LiquidityDelta calldata deltas, bytes calldata extensionData)
        external
        returns (uint256 amount0Removed, uint256 amount1Removed);
}

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
}
