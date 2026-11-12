// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "src/onyx/MockERC20.sol";
import {SimpleFeeVault} from "src/onyx/SimpleFeeVault.sol";

/// @notice Local (no RPC) fuzz of share-price and entry/exit-fee rounding properties
/// reviewed on Enzyme Onyx vaults. Uses a small model vault, not protocol source.
contract SharePriceInvariantsTest is Test {
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");
    address internal feeRecipient = makeAddr("feeRecipient");

    function _deploy(uint8 dec, uint16 entryBps, uint16 exitBps, address exitRecipient)
        internal
        returns (MockERC20 asset, SimpleFeeVault vault)
    {
        asset = new MockERC20(dec);
        vault = new SimpleFeeVault(asset, entryBps, exitBps, exitRecipient);
    }

    function test_depositRedeemAtSamePriceNeverProfits() public {
        (MockERC20 asset, SimpleFeeVault vault) = _deploy(18, 0, 0, address(0));
        uint256 amount = 1_000e18;
        asset.mint(attacker, amount);
        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount);
        uint256 out = vault.redeem(shares);
        vm.stopPrank();
        assertLe(out, amount);
        assertLe(asset.balanceOf(attacker), amount);
    }

    /// @dev Deposit then redeem at the same cached share price must not pay out
    ///      more than was deposited, across decimals, rates, and fee settings.
    function testFuzz_roundTripNeverProfitable(
        uint8 decSeed,
        uint256 sharePrice,
        uint256 amount,
        uint16 entryBps,
        uint16 exitBps,
        bool exitRecipientZero
    ) public {
        uint8 dec = uint8(bound(decSeed, 0, 24));
        entryBps = uint16(bound(entryBps, 0, 9999));
        exitBps = uint16(bound(exitBps, 0, 9999));
        sharePrice = bound(sharePrice, 1, 1e36);
        amount = bound(amount, 1, 1e36);

        (MockERC20 asset, SimpleFeeVault vault) =
            _deploy(dec, entryBps, exitBps, exitRecipientZero ? address(0) : feeRecipient);

        // Seed supply, then move the cached share price, same shape as a live vault.
        uint256 seed = 10 ** (dec == 0 ? 1 : dec) * 1000;
        if (seed == 0) seed = 1000;
        asset.mint(alice, seed);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        try vault.deposit(seed) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        vault.setSharePrice(sharePrice);

        asset.mint(attacker, amount);
        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        uint256 got;
        try vault.deposit(amount) returns (uint256 s) {
            assertEq(vault.balanceOf(attacker), s);
            try vault.redeem(s) returns (uint256 a) {
                got = a;
            } catch {}
        } catch {}
        vm.stopPrank();
        assertLe(asset.balanceOf(attacker), amount, "round trip profit");
        assertLe(got, amount);
    }

    /// @dev Splitting a redeem into tiny chunks (where exit fee floors to 0) must
    ///      not pay out more than the shares being redeemed.
    function testFuzz_splitRedeemFeeDodge(uint16 exitBps, uint256 n) public {
        exitBps = uint16(bound(exitBps, 1, 9999));
        n = bound(n, 1, 50);
        (MockERC20 asset, SimpleFeeVault vault) = _deploy(18, 0, exitBps, feeRecipient);
        asset.mint(attacker, 1e30);
        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1e24);
        vm.stopPrank();
        vault.setSharePrice(1e18);

        uint256 chunk = 10_000 / exitBps; // fee floors to 0 when gross * bps < 10_000
        if (chunk == 0) return;
        uint256 before = asset.balanceOf(attacker);
        vm.startPrank(attacker);
        for (uint256 i; i < n; i++) {
            try vault.redeem(chunk) {} catch {}
        }
        vm.stopPrank();
        uint256 gain = asset.balanceOf(attacker) - before;
        assertLe(gain, chunk * n);
    }

    function test_redeemAllReturnsAtMostTotalAssets() public {
        (MockERC20 asset, SimpleFeeVault vault) = _deploy(18, 50, 50, feeRecipient);
        asset.mint(alice, 100e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100e18);
        uint256 shares = vault.balanceOf(alice);
        uint256 held = vault.totalAssets();
        uint256 out = vault.redeem(shares);
        vm.stopPrank();
        assertLe(out, held);
        assertEq(vault.totalSupply(), 0);
    }
}
