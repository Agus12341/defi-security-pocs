// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkOrSkip} from "src/ForkOrSkip.sol";
import {
    IComptroller,
    ICToken,
    ICEther,
    IERC20Minimal,
    IUSDT
} from "src/capyfi/Interfaces.sol";

/// @notice Live-fork checks against CapyFi's Ethereum Unitroller.
/// @dev Needs ETH_RPC_URL. Skips if the env var is unset.
contract CapyLiveTest is ForkOrSkip {
    address constant UNITROLLER = 0x0b9af1fd73885aD52680A1aeAa7A3f17AC702afA;
    address constant CA_USDC = 0xc3aD34De18B59A24BD0877e454Fb924181F09C8f;
    address constant CA_USDT = 0x0f864A3e50D1070adDE5100fd848446C0567362B;
    address constant CA_ETH = 0x37DE57183491Fa9745d8Fa5DCd950f0c3a4645c9;
    address constant CA_WMXN = 0x59B8022F431C7f00eF4894895c2F6bB1986f9acC;
    address constant CA_LAC = 0x0568F6cb5A0E84FACa107D02f81ddEB1803f3B50;
    address constant CA_RPC = 0xF61159B4a0EE5b1615c9Afb3dA38111043344c32;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WMXN = 0x337E7456B420bD3481e7FA61fA9850343d610d34;

    function setUp() public {
        forkEth();
    }

    function _exchangeIdentity(address market) internal view {
        ICToken c = ICToken(market);
        uint256 supply = c.totalSupply();
        if (supply == 0) return;
        uint256 expected = ((c.getCash() + c.totalBorrows() - c.totalReserves()) * 1e18) / supply;
        assertEq(c.exchangeRateStored(), expected, string.concat("ER mismatch ", c.symbol()));
    }

    function test_AllMarketsExchangeRateIdentity() public view {
        address[] memory markets = IComptroller(UNITROLLER).getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            _exchangeIdentity(markets[i]);
        }
    }

    function test_UsdcMintRedeemRoundTrip() public {
        address user = makeAddr("user");
        uint256 amount = 1_000e6;
        deal(USDC, user, amount);
        vm.startPrank(user);
        IERC20Minimal(USDC).approve(CA_USDC, type(uint256).max);
        uint256 tsBefore = ICToken(CA_USDC).totalSupply();
        require(ICToken(CA_USDC).mint(amount) == 0, "mint failed");
        uint256 caBal = ICToken(CA_USDC).balanceOf(user);
        require(ICToken(CA_USDC).redeem(caBal) == 0, "redeem failed");
        uint256 end = IERC20Minimal(USDC).balanceOf(user);
        assertLe(amount - end, 2);
        assertApproxEqAbs(ICToken(CA_USDC).totalSupply(), tsBefore, 1);
        _exchangeIdentity(CA_USDC);
        vm.stopPrank();
    }

    function test_EthMintRedeemRoundTrip() public {
        address user = makeAddr("ethuser");
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 tsBefore = ICEther(CA_ETH).totalSupply();
        ICEther(CA_ETH).mint{value: 0.5 ether}();
        uint256 caBal = ICEther(CA_ETH).balanceOf(user);
        assertGt(caBal, 0);
        require(ICEther(CA_ETH).redeem(caBal) == 0, "redeem");
        // Interest may accrue between mint and redeem.
        assertGe(user.balance, 1 ether - 0.01 ether);
        assertApproxEqAbs(ICEther(CA_ETH).totalSupply(), tsBefore, 1);
        vm.stopPrank();
    }

    function test_UsdtBorrowRepayAgainstUsdc() public {
        address user = makeAddr("borrower");
        deal(USDC, user, 5_000e6);
        vm.startPrank(user);
        IERC20Minimal(USDC).approve(CA_USDC, type(uint256).max);
        require(ICToken(CA_USDC).mint(5_000e6) == 0, "mint");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_USDC;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        require(ICToken(CA_USDT).borrow(1_000e6) == 0, "borrow");
        IUSDT(USDT).approve(CA_USDT, 0);
        IUSDT(USDT).approve(CA_USDT, type(uint256).max);
        require(ICToken(CA_USDT).repayBorrow(type(uint256).max) == 0, "repay");
        assertEq(ICToken(CA_USDT).borrowBalanceStored(user), 0);
        vm.stopPrank();
    }

    /// @dev Empty-market exchange-rate inflation (Hundred/Sonne/Onyx class) is blocked
    ///      while the FX market collateral factor is 0.
    function test_WmxnDonationCannotBorrowAgainstInflatedCollateral() public {
        address attacker = makeAddr("attacker");
        uint256 donateAmt = 1_000_000e18;
        deal(WMXN, attacker, donateAmt + 1e18);
        vm.startPrank(attacker);
        IERC20Minimal(WMXN).approve(CA_WMXN, type(uint256).max);
        require(ICToken(CA_WMXN).mint(1e18) == 0, "mint dust");
        require(IERC20Minimal(WMXN).transfer(CA_WMXN, donateAmt), "donate");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_WMXN;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        (, uint256 liq,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertEq(liq, 0, "CF=0 must yield zero liquidity");
        vm.expectRevert();
        ICToken(CA_USDC).borrow(1e6);
        vm.stopPrank();
    }

    function test_LacAndRpcMintBlockedForNonWhitelisted() public {
        address user = makeAddr("nowl");
        address lac = ICToken(CA_LAC).underlying();
        address rpc = ICToken(CA_RPC).underlying();
        deal(lac, user, 1e18);
        deal(rpc, user, 1e18);
        vm.startPrank(user);
        IERC20Minimal(lac).approve(CA_LAC, type(uint256).max);
        IERC20Minimal(rpc).approve(CA_RPC, type(uint256).max);
        vm.expectRevert(bytes("WhitelistAccess: not whitelisted"));
        ICToken(CA_LAC).mint(1e18);
        vm.expectRevert(bytes("WhitelistAccess: not whitelisted"));
        ICToken(CA_RPC).mint(1e18);
        vm.stopPrank();
    }

    /// @dev Same inflation path only produces borrow liquidity after the admin sets CF.
    function test_InflationRequiresAdminCollateralFactor() public {
        address attacker = makeAddr("attacker2");
        address admin = IComptroller(UNITROLLER).admin();
        uint256 donateAmt = 100_000e18;
        deal(WMXN, attacker, donateAmt + 1e18);

        vm.startPrank(attacker);
        IERC20Minimal(WMXN).approve(CA_WMXN, type(uint256).max);
        require(ICToken(CA_WMXN).mint(1e18) == 0, "mint");
        require(IERC20Minimal(WMXN).transfer(CA_WMXN, donateAmt), "donate");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_WMXN;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        (, uint256 liqBefore,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertEq(liqBefore, 0);
        vm.stopPrank();

        vm.prank(admin);
        uint256 cfErr = IComptroller(UNITROLLER)._setCollateralFactor(CA_WMXN, 0.8e18);
        assertEq(cfErr, 0, "admin CF set should succeed");

        (, uint256 liqAfter,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertGt(liqAfter, 0, "liquidity appears only after a privileged CF set");
    }

    function test_ForcedLiquidationUsdcCollateralUsdtDebt() public {
        address borrower = makeAddr("liqBorrower");
        address liquidator = makeAddr("liquidator");
        deal(USDC, borrower, 2_000e6);
        deal(USDT, liquidator, 2_000e6);

        vm.startPrank(borrower);
        IERC20Minimal(USDC).approve(CA_USDC, type(uint256).max);
        require(ICToken(CA_USDC).mint(2_000e6) == 0, "mint");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_USDC;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        require(ICToken(CA_USDT).borrow(1_000e6) == 0, "borrow");
        vm.stopPrank();

        // Lower CF to force shortfall, standing in for a collateral price drop.
        address admin = IComptroller(UNITROLLER).admin();
        vm.prank(admin);
        require(IComptroller(UNITROLLER)._setCollateralFactor(CA_USDC, 0.1e18) == 0, "cf");

        (,, uint256 shortfall) = IComptroller(UNITROLLER).getAccountLiquidity(borrower);
        assertGt(shortfall, 0, "need shortfall");

        vm.startPrank(liquidator);
        IUSDT(USDT).approve(CA_USDT, 0);
        IUSDT(USDT).approve(CA_USDT, type(uint256).max);
        uint256 repay = 200e6;
        require(ICToken(CA_USDT).liquidateBorrow(borrower, repay, CA_USDC) == 0, "liquidate");
        assertGt(ICToken(CA_USDC).balanceOf(liquidator), 0);
        vm.stopPrank();
        _exchangeIdentity(CA_USDC);
        _exchangeIdentity(CA_USDT);
    }
}
