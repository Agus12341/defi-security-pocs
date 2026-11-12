// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkOrSkip} from "src/ForkOrSkip.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IShares {
    function getValuationHandler() external view returns (address);
    function owner() external view returns (address);
}

interface IValuationHandler {
    function getSharePrice() external view returns (uint256 price, uint256 timestamp);
}

interface ISyncDepositHandler {
    function getMaxSharePriceStaleness() external view returns (uint256);
    function getDepositorAllowlist() external view returns (address);
    function deposit(uint256 amount) external returns (uint256 shares);
}

interface IRedeemQueue {
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);
    function executeRedeemRequests(uint256[] calldata ids) external;
    function asset() external view returns (address);
}

/// @notice Fork checks against live Ethereum Enzyme Onyx vaults.
/// @dev Needs ETH_RPC_URL. Skips if the env var is unset. Nothing is broadcast.
contract OnyxForkLiveTest is ForkOrSkip {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    struct Target {
        string name;
        address shares;
        address syncDeposit;
        address redeemQueue;
    }

    function _targets() internal pure returns (Target[] memory t) {
        t = new Target[](3);
        t[0] = Target(
            "Unsquared",
            0x113f68cb6e9Adf3DA5952981AA85EFfbd92Ff1F0,
            0x6813AC9cfF361A1b3Cb33363bfE4322cf60F256E,
            0x5024ef7d345a02C4Cf25Bd454ba9d2F1f8F3Dcee
        );
        t[1] = Target(
            "CREDI",
            0x17Bc294c9c07fA9e3C3f6aBA0d5F613c89D3760B,
            0xaAc0432D96AAba64c31a04644E55D6C44ff9630B,
            0xB31405157f0049e2FefdA90253F4ed2c3d5A6673
        );
        t[2] = Target(
            "Ensuro",
            0xEee7520554A18872a046F736FF262B8E4E0D0b2A,
            0x226B28D544Fcce98F77f83F18A2A570761eb0BAa,
            0x3D7C64D24D3936f462b515127Aa69C808Fa22AC8
        );
    }

    function setUp() public {
        forkEth();
    }

    /// @dev Sync deposit then queued redeem at the same cached share price
    ///      must not profit an unprivileged depositor.
    function test_liveSyncDepositThenQueuedRedeem_noProfit() public {
        Target[] memory ts = _targets();
        for (uint256 i; i < ts.length; i++) {
            Target memory t = ts[i];
            IShares shares = IShares(t.shares);
            ISyncDepositHandler sdh = ISyncDepositHandler(t.syncDeposit);
            IRedeemQueue rq = IRedeemQueue(t.redeemQueue);
            IValuationHandler vh = IValuationHandler(shares.getValuationHandler());
            (uint256 price, uint256 ts_) = vh.getSharePrice();
            emit log_named_string("vault", t.name);
            emit log_named_uint("  cached share price", price);
            emit log_named_uint("  price age (s)", block.timestamp - ts_);
            emit log_named_uint("  sync maxStaleness", sdh.getMaxSharePriceStaleness());
            emit log_named_address("  depositor allowlist", sdh.getDepositorAllowlist());

            address user = makeAddr(string.concat("user", t.name));
            uint256 amt = 100_000e6;
            deal(USDC, user, amt);
            vm.startPrank(user);
            IERC20(USDC).approve(address(sdh), amt);
            uint256 sharesOut;
            try sdh.deposit(amt) returns (uint256 s) {
                sharesOut = s;
            } catch (bytes memory r) {
                emit log_named_bytes("  deposit reverted", r);
                vm.stopPrank();
                continue;
            }
            emit log_named_uint("  shares minted", sharesOut);
            uint256 rid = rq.requestRedeem(sharesOut, user, user);
            vm.stopPrank();

            uint256[] memory ids = new uint256[](1);
            ids[0] = rid;
            vm.prank(shares.owner());
            try rq.executeRedeemRequests(ids) {}
            catch (bytes memory r) {
                emit log_named_bytes("  exec reverted", r);
                continue;
            }
            uint256 back = IERC20(rq.asset()).balanceOf(user);
            emit log_named_uint("  assets back", back);
            emit log_named_address("  redeem asset", rq.asset());
            if (rq.asset() == USDC) assertLe(back, amt, "profit on round trip");
        }
    }
}
