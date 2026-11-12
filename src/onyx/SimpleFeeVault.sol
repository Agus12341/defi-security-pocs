// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice Minimal fee-charging vault used to fuzz share-price and fee-rounding
/// properties reviewed on Enzyme Onyx sync deposit / redeem paths.
/// This is not Enzyme source and is not a deployable protocol vault.
///
/// Accounting: `sharePrice` is asset units per 1e18 shares (admin-set, like a
/// cached share value). Entry fee is taken from assets in; exit fee from assets
/// out. Conversion floors, so a same-price round trip must not profit the user.
contract SimpleFeeVault {
    MockERC20 public immutable asset;
    uint16 public immutable entryBps;
    uint16 public immutable exitBps;
    address public immutable feeRecipient;

    uint256 public sharePrice;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev `feeRecipient` may be zero, in which case fees stay in the vault.
    constructor(MockERC20 _asset, uint16 _entryBps, uint16 _exitBps, address _feeRecipient) {
        require(_entryBps < 10_000 && _exitBps < 10_000, "bps");
        asset = _asset;
        entryBps = _entryBps;
        exitBps = _exitBps;
        feeRecipient = _feeRecipient;
        sharePrice = 1e18;
    }

    function setSharePrice(uint256 price) external {
        require(price > 0, "price");
        sharePrice = price;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * 1e18) / sharePrice;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * sharePrice) / 1e18;
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        uint256 fee = (assets * entryBps) / 10_000;
        shares = convertToShares(assets - fee);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        uint256 gross = convertToAssets(shares);
        uint256 fee = (gross * exitBps) / 10_000;
        assets = gross - fee;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = previewDeposit(assets);
        require(shares > 0, "zero shares");
        require(asset.transferFrom(msg.sender, address(this), assets), "transfer in");
        uint256 fee = (assets * entryBps) / 10_000;
        if (fee > 0 && feeRecipient != address(0)) {
            require(asset.transfer(feeRecipient, fee), "fee");
        }
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
        emit Transfer(address(0), msg.sender, shares);
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        require(balanceOf[msg.sender] >= shares, "bal");
        assets = previewRedeem(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        emit Transfer(msg.sender, address(0), shares);
        uint256 gross = convertToAssets(shares);
        uint256 fee = gross - assets;
        if (fee > 0 && feeRecipient != address(0)) {
            require(asset.transfer(feeRecipient, fee), "fee");
        }
        require(asset.transfer(msg.sender, assets), "transfer out");
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
