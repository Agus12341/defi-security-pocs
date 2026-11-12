// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkOrSkip} from "src/ForkOrSkip.sol";
import {
    IMetricOmmPool,
    IMetricOmmSwapCallback,
    IMetricOmmModifyLiquidityCallback,
    IERC20Minimal,
    IWETH9,
    LiquidityDelta,
    PoolImmutables
} from "src/metric/LiveInterfaces.sol";

/// @notice Defensive invariant tests against locally forked live Metric pools.
/// @dev Asserts secure behaviour (no round-trip profit, add/remove does not mint
///      free tokens, a stalled price provider reverts rather than quoting a bad
///      price). Needs ETH_RPC_URL / BSC_RPC_URL; each test skips if its RPC is unset.
contract LiveInvariants is ForkOrSkip, IMetricOmmSwapCallback, IMetricOmmModifyLiquidityCallback {
    uint256 internal constant ETH_FORK_BLOCK = 26_391_713;
    uint256 internal constant BSC_FORK_BLOCK = 132_969_187;

    // Highest-TVL quote-OK pools from a 11 Nov 2026 enumeration.
    address internal constant ETH_USDC_USDT = 0xaef2ad7aBB651945e6D24276715f25BDED0ad41e;
    address internal constant ETH_SUSDE_USDE = 0x5b9D015787d1e1b91F1EDAacC214Aa75090A5493;
    address internal constant ETH_WSTETH_WETH = 0x77b21ddC997a450Ae34100eEcd352020E3f53BaA;
    address internal constant BSC_WBNB_USDT = 0xF3eb104C0773d79F69caBF1DA938153cE0efAFd6;
    address internal constant BSC_USDC_USDT = 0xb3aDeb4a72948f68CcdC8C958a0bE4BCEa3C0677;

    address internal payToken0;
    address internal payToken1;

    function _rawApprove(address token, address spender, uint256 value) internal {
        // USDT on Ethereum may require a zero-approval first and may omit a return value.
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        ok;
        (bool ok2, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, value));
        require(ok2 && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _balance(address token, address who) internal view returns (uint256) {
        return IERC20Minimal(token).balanceOf(who);
    }

    function metricOmmSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        if (amount0Delta > 0) {
            _pay(payToken0, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            _pay(payToken1, msg.sender, uint256(amount1Delta));
        }
    }

    function metricOmmModifyLiquidityCallback(uint256 amount0Delta, uint256 amount1Delta, bytes calldata)
        external
        override
    {
        if (amount0Delta > 0) {
            _pay(payToken0, msg.sender, amount0Delta);
        }
        if (amount1Delta > 0) {
            _pay(payToken1, msg.sender, amount1Delta);
        }
    }

    function _pay(address token, address to, uint256 value) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "token transfer failed");
    }

    function _seed(address token, uint256 amount) internal {
        deal(token, address(this), amount, true);
    }

    function _swapExactIn(address pool, bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        PoolImmutables memory imm = IMetricOmmPool(pool).getImmutables();
        payToken0 = imm.token0;
        payToken1 = imm.token1;
        uint256 outBefore = zeroForOne ? _balance(imm.token1, address(this)) : _balance(imm.token0, address(this));
        IMetricOmmPool(pool).swap(
            address(this), zeroForOne, int128(int256(amountIn)), zeroForOne ? uint128(0) : type(uint128).max, "", ""
        );
        uint256 outAfter = zeroForOne ? _balance(imm.token1, address(this)) : _balance(imm.token0, address(this));
        amountOut = outAfter - outBefore;
    }

    function _assertRoundTripNoProfit(address pool, bool startZeroForOne, uint256 amountIn, uint256 maxDust)
        internal
    {
        PoolImmutables memory imm = IMetricOmmPool(pool).getImmutables();
        address tokenIn = startZeroForOne ? imm.token0 : imm.token1;
        _seed(tokenIn, amountIn);
        uint256 startBal = _balance(tokenIn, address(this));
        uint256 midOut = _swapExactIn(pool, startZeroForOne, amountIn);
        require(midOut > 0, "first hop produced zero output");
        _swapExactIn(pool, !startZeroForOne, midOut);
        uint256 endBal = _balance(tokenIn, address(this));
        if (endBal > startBal) {
            uint256 profit = endBal - startBal;
            assertLe(profit, maxDust, "round-trip produced profit above dust bound");
        }
    }

    function test_eth_usdcUsdt_quoteLens_succeeds() public {
        forkEthAt(ETH_FORK_BLOCK);
        (uint128 sell, uint128 buy) = IMetricOmmPool(ETH_USDC_USDT).getSellAndBuyPrices();
        assertGt(sell, 0);
        assertGt(buy, sell);
    }

    function test_eth_usdcUsdt_roundTrip_zeroForOne_noProfit() public {
        forkEthAt(ETH_FORK_BLOCK);
        _assertRoundTripNoProfit(ETH_USDC_USDT, true, 1_000 * 1e6, 1);
    }

    function test_eth_usdcUsdt_roundTrip_oneForZero_noProfit() public {
        forkEthAt(ETH_FORK_BLOCK);
        _assertRoundTripNoProfit(ETH_USDC_USDT, false, 1_000 * 1e6, 1);
    }

    function test_eth_susdeUsde_roundTrip_noProfit() public {
        forkEthAt(ETH_FORK_BLOCK);
        _assertRoundTripNoProfit(ETH_SUSDE_USDE, true, 100 * 1e18, 1e10);
    }

    function test_eth_wstethWeth_roundTrip_noProfit() public {
        forkEthAt(ETH_FORK_BLOCK);
        _assertRoundTripNoProfit(ETH_WSTETH_WETH, true, 1e17, 1e8);
    }

    function test_eth_usdcUsdt_addRemove_doesNotMintFreeTokens() public {
        forkEthAt(ETH_FORK_BLOCK);
        _assertAddRemoveDoesNotMintFreeTokens(ETH_USDC_USDT);
    }

    function _addDelta(IMetricOmmPool pool, uint256 minOp) internal view returns (LiquidityDelta memory d) {
        int256[] memory bins = new int256[](1);
        bins[0] = 2;
        uint256[] memory sharesArr = new uint256[](1);
        uint256 binTotalShares = uint256(vm.load(address(pool), keccak256(abi.encode(int256(2), uint256(5)))));
        uint256 want = binTotalShares / 10_000;
        if (want < minOp * 1_000_000) want = minOp * 1_000_000;
        sharesArr[0] = want;
        d = LiquidityDelta({binIdxs: bins, shares: sharesArr});
    }

    function _assertAddRemoveDoesNotMintFreeTokens(address poolAddr) internal {
        IMetricOmmPool pool = IMetricOmmPool(poolAddr);
        PoolImmutables memory imm = pool.getImmutables();
        payToken0 = imm.token0;
        payToken1 = imm.token1;
        _seed(imm.token0, 50_000 * 1e6);
        _seed(imm.token1, 50_000 * 1e6);
        uint256 b0 = _balance(imm.token0, address(this));
        uint256 b1 = _balance(imm.token1, address(this));

        LiquidityDelta memory d = _addDelta(pool, imm.minimalOperationalLiquidity);
        (uint256 a0, uint256 a1) = pool.addLiquidity(address(this), 1, d, "", "");
        (uint256 r0, uint256 r1) = pool.removeLiquidity(address(this), 1, d, "");

        assertLe(_balance(imm.token0, address(this)), b0, "token0 increased after add/remove");
        assertLe(_balance(imm.token1, address(this)), b1, "token1 increased after add/remove");
        assertTrue(a0 + a1 > 0 && r0 + r1 > 0, "no liquidity moved");
    }

    function test_bsc_wbnbUsdt_quoteLens_and_roundTrip_noProfit() public {
        forkBscAt(BSC_FORK_BLOCK);
        (uint128 sell, uint128 buy) = IMetricOmmPool(BSC_WBNB_USDT).getSellAndBuyPrices();
        assertGt(sell, 0);
        assertGt(buy, sell);
        // WBNB has no ordinary ERC-20 balance slot that `deal` can find; wrap native instead.
        uint256 amountIn = 5e16;
        PoolImmutables memory imm = IMetricOmmPool(BSC_WBNB_USDT).getImmutables();
        vm.deal(address(this), amountIn);
        IWETH9(imm.token0).deposit{value: amountIn}();
        uint256 startBal = _balance(imm.token0, address(this));
        payToken0 = imm.token0;
        payToken1 = imm.token1;
        uint256 midOut = _swapExactIn(BSC_WBNB_USDT, true, amountIn);
        require(midOut > 0, "first hop produced zero output");
        _swapExactIn(BSC_WBNB_USDT, false, midOut);
        uint256 endBal = _balance(imm.token0, address(this));
        if (endBal > startBal) {
            assertLe(endBal - startBal, 1e8, "round-trip produced profit above dust bound");
        }
    }

    function test_eth_stalledAppPool_quoteReverts() public {
        forkEthAt(ETH_FORK_BLOCK);
        // WETH/USDC pool whose price provider was stalled at this block.
        // The pool must revert on quote rather than return a bad price.
        address stalled = 0xE9c19e5Bd10E5096519fe1D2a9D783F79B8211Da;
        vm.expectRevert();
        IMetricOmmPool(stalled).getSellAndBuyPrices();
    }

    function test_bsc_usdcUsdt_roundTrip_noProfit() public {
        forkBscAt(BSC_FORK_BLOCK);
        (uint128 sell, uint128 buy) = IMetricOmmPool(BSC_USDC_USDT).getSellAndBuyPrices();
        assertGt(sell, 0);
        assertGt(buy, sell);
        _assertRoundTripNoProfit(BSC_USDC_USDT, true, 1_000 * 1e18, 1e6);
    }
}
