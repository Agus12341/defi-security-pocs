// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// @notice Forks when the named RPC env var is set; otherwise skips the test.
abstract contract ForkOrSkip is Test {
    function forkEth() internal {
        _fork("ETH_RPC_URL", 0);
    }

    function forkEthAt(uint256 blockNumber) internal {
        _fork("ETH_RPC_URL", blockNumber);
    }

    function forkBscAt(uint256 blockNumber) internal {
        _fork("BSC_RPC_URL", blockNumber);
    }

    function _fork(string memory key, uint256 blockNumber) internal {
        string memory rpc = vm.envOr(key, string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        if (blockNumber == 0) {
            uint256 forkId = vm.createSelectFork(rpc);
            forkId;
        } else {
            uint256 forkId = vm.createSelectFork(rpc, blockNumber);
            forkId;
        }
    }
}
