// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkOrSkip} from "src/ForkOrSkip.sol";
import {
    IComptroller,
    ICToken,
    IERC20Minimal,
    ILatamStable,
    IOracle,
    IAgg
} from "src/capyfi/Interfaces.sol";

/// @notice Live-fork checks on CapyFi FX markets (wARS, wBRL, wMXN, wCOP, USDAR).
/// @dev Needs ETH_RPC_URL. Skips if the env var is unset. `deal` does not hit
///      OZ v5 ERC-20 storage, so FX underlyings are credited via the known slot.
contract FxMarketsTest is ForkOrSkip {
    address constant UNITROLLER = 0x0b9af1fd73885aD52680A1aeAa7A3f17AC702afA;
    address constant CA_USDC = 0xc3aD34De18B59A24BD0877e454Fb924181F09C8f;
    address constant CA_WARS = 0xf80eeec09f417Fa7FCc4A848Ef03af9dF2658d7B;
    address constant CA_WBRL = 0x93d9DdEeBf3B5DBF7D7dFC04D3804Ce5450987C8;
    address constant CA_WMXN = 0x59B8022F431C7f00eF4894895c2F6bB1986f9acC;
    address constant CA_WCOP = 0xe9b369ee5a75a71d2981E5Fcb4b5011293Cf8fdB;
    address constant CA_USDAR = 0x2437E33631327b2437170972f753E15Cb9Fd1806;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WARS = 0x0DC4F92879B7670e5f4e4e6e3c801D229129D90D;
    address constant WBRL = 0xD76f5Faf6888e24D9F04Bf92a0c8B921FE4390e0;
    address constant WMXN = 0x337E7456B420bD3481e7FA61fA9850343d610d34;
    address constant WCOP = 0x8a1D45e102e886510e891d2Ec656a708991e2D76;
    address constant USDAR = 0xdcC340132740AD57E9Fc90C9BD08B00dBbc87986;

    // OZ v5 ERC20Storage namespace. balances at +0, totalSupply at +2.
    uint256 constant ERC20_NS = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function setUp() public {
        forkEth();
    }

    function _dealLatam(address token, address to, uint256 amount) internal {
        bytes32 balSlot = keccak256(abi.encode(to, ERC20_NS));
        uint256 cur = uint256(vm.load(token, balSlot));
        vm.store(token, balSlot, bytes32(cur + amount));
        bytes32 tsSlot = bytes32(ERC20_NS + 2);
        uint256 ts = uint256(vm.load(token, tsSlot));
        vm.store(token, tsSlot, bytes32(ts + amount));
    }

    function _erIdentity(address market) internal view {
        ICToken c = ICToken(market);
        uint256 supply = c.totalSupply();
        if (supply == 0) return;
        uint256 expected = ((c.getCash() + c.totalBorrows() - c.totalReserves()) * 1e18) / supply;
        assertEq(c.exchangeRateStored(), expected, string.concat("ER ", c.symbol()));
    }

    function test_FxMarketsExchangeRateIdentity() public view {
        _erIdentity(CA_WARS);
        _erIdentity(CA_WBRL);
        _erIdentity(CA_WMXN);
        _erIdentity(CA_WCOP);
        _erIdentity(CA_USDAR);
    }

    function test_FxDonationCannotUnlockLiquidityWithoutAdminCf() public {
        address attacker = makeAddr("attacker");
        _dealLatam(WMXN, attacker, 1_000_000e18);
        vm.startPrank(attacker);
        IERC20Minimal(WMXN).approve(CA_WMXN, type(uint256).max);
        require(ICToken(CA_WMXN).mint(1e18) == 0, "mint");
        require(IERC20Minimal(WMXN).transfer(CA_WMXN, 999_999e18), "donate");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_WMXN;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        (, uint256 liq,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertEq(liq, 0, "CF=0 must give 0 liquidity after donation");
        vm.expectRevert();
        ICToken(CA_USDC).borrow(1e6);
        vm.stopPrank();
    }

    function test_AdminCfUnlocksWmxnInflation() public {
        address attacker = makeAddr("attacker2");
        _dealLatam(WMXN, attacker, 1_000_000e18);
        vm.startPrank(attacker);
        IERC20Minimal(WMXN).approve(CA_WMXN, type(uint256).max);
        require(ICToken(CA_WMXN).mint(1e18) == 0, "mint");
        require(IERC20Minimal(WMXN).transfer(CA_WMXN, 999_999e18), "donate");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_WMXN;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        vm.stopPrank();

        address admin = IComptroller(UNITROLLER).admin();
        vm.prank(admin);
        require(IComptroller(UNITROLLER)._setCollateralFactor(CA_WMXN, 0.8e18) == 0, "setCF");

        (, uint256 liq,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertGt(liq, 0, "liquidity appears only after a privileged CF set");
    }

    function test_PauseUnderlyingIsRoleGatedAndRedeemWorksWhileUnpaused() public {
        address user = makeAddr("supplier");
        _dealLatam(WARS, user, 1000e18);
        vm.startPrank(user);
        IERC20Minimal(WARS).approve(CA_WARS, type(uint256).max);
        require(ICToken(CA_WARS).mint(1000e18) == 0, "mint");
        uint256 shares = ICToken(CA_WARS).balanceOf(user);
        vm.stopPrank();

        address random = makeAddr("notPauser");
        vm.prank(random);
        vm.expectRevert();
        ILatamStable(WARS).pause();

        assertFalse(ILatamStable(WARS).paused());
        vm.startPrank(user);
        require(ICToken(CA_WARS).redeem(shares) == 0, "redeem ok while unpaused");
        vm.stopPrank();
    }

    function test_UsdarBlocklistOffAndComplianceGated() public {
        assertFalse(ILatamStable(USDAR).enforceBlocklist());
        address random = makeAddr("rando");
        vm.prank(random);
        vm.expectRevert();
        ILatamStable(USDAR).setEnforceBlocklist(true);

        address compliance = 0x5CA3F8EEBa12D83408fc097c2dAd79212456F20F;
        assertTrue(ILatamStable(USDAR).hasRole(ILatamStable(USDAR).COMPLIANCE_ROLE(), compliance));
    }

    function test_WarsMintRedeemRoundTrip() public {
        address user = makeAddr("warsUser");
        uint256 amount = 1_000_000e18;
        _dealLatam(WARS, user, amount);
        vm.startPrank(user);
        IERC20Minimal(WARS).approve(CA_WARS, type(uint256).max);
        require(ICToken(CA_WARS).mint(amount) == 0, "mint");
        uint256 shares = ICToken(CA_WARS).balanceOf(user);
        require(ICToken(CA_WARS).redeem(shares) == 0, "redeem");
        uint256 end = IERC20Minimal(WARS).balanceOf(user);
        // Interest can accrue between mint and redeem; allow a small gap.
        assertGe(end + 100e18, amount);
        _erIdentity(CA_WARS);
        vm.stopPrank();
    }

    function test_BorrowWarsAgainstUsdc() public {
        address user = makeAddr("warsBorrower");
        deal(USDC, user, 50_000e6);
        vm.startPrank(user);
        IERC20Minimal(USDC).approve(CA_USDC, type(uint256).max);
        require(ICToken(CA_USDC).mint(50_000e6) == 0, "mint usdc");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_USDC;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        uint256 warsCash = ICToken(CA_WARS).getCash();
        uint256 borrowAmt = warsCash / 1000;
        if (borrowAmt == 0) borrowAmt = 1e18;
        require(ICToken(CA_WARS).borrow(borrowAmt) == 0, "borrow wars");
        assertEq(IERC20Minimal(WARS).balanceOf(user), borrowAmt);
        _dealLatam(WARS, user, borrowAmt * 2);
        IERC20Minimal(WARS).approve(CA_WARS, type(uint256).max);
        ICToken(CA_WARS).repayBorrow(type(uint256).max);
        vm.stopPrank();
        _erIdentity(CA_WARS);
    }

    /// @dev The oracle does not gate on feed freshness (acknowledged Coinspect CAPY-02).
    ///      After the feed is aged in the fork, getUnderlyingPrice still returns a price.
    function test_OracleServesPriceAfterFeedGoesStale() public {
        address oracle = IComptroller(UNITROLLER).oracle();
        (, address feed,) = IOracle(oracle).getConfig(CA_USDAR);
        (,,, uint256 updatedAt,) = IAgg(feed).latestRoundData();
        vm.warp(updatedAt + 30 days);
        uint256 px = IOracle(oracle).getUnderlyingPrice(CA_USDAR);
        assertGt(px, 0, "oracle still returns a price after the feed is stale");
    }

    function test_FxOracleScalingMatchesFeed() public view {
        address oracle = IComptroller(UNITROLLER).oracle();
        address[5] memory markets = [CA_WARS, CA_WBRL, CA_WMXN, CA_WCOP, CA_USDAR];
        for (uint256 i = 0; i < markets.length; i++) {
            (uint8 undDec, address feed, uint256 fixedP) = IOracle(oracle).getConfig(markets[i]);
            assertEq(fixedP, 0);
            assertEq(undDec, 18);
            (, int256 answer,,,) = IAgg(feed).latestRoundData();
            uint8 fd = IAgg(feed).decimals();
            uint256 expected = uint256(answer) * (10 ** (36 - fd - undDec));
            assertEq(IOracle(oracle).getUnderlyingPrice(markets[i]), expected, ICToken(markets[i]).symbol());
        }
    }

    function test_UsdarEmptyMarketInflationPermissionlessBlocked() public {
        address attacker = makeAddr("usdarAttack");
        _dealLatam(USDAR, attacker, 1_000_000e18);
        vm.startPrank(attacker);
        IERC20Minimal(USDAR).approve(CA_USDAR, type(uint256).max);
        require(ICToken(CA_USDAR).mint(1e18) == 0, "mint");
        require(IERC20Minimal(USDAR).transfer(CA_USDAR, 999_999e18), "donate");
        address[] memory mkts = new address[](1);
        mkts[0] = CA_USDAR;
        IComptroller(UNITROLLER).enterMarkets(mkts);
        (, uint256 liq,) = IComptroller(UNITROLLER).getAccountLiquidity(attacker);
        assertEq(liq, 0, "CF=0 blocks inflation drain");
        vm.stopPrank();
    }
}
