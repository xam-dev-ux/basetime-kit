// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BaseTimeLib, IBaseTime} from "../../src/BaseTimeLib.sol";
import {BlockRateOracle} from "../../src/BlockRateOracle.sol";

contract LiveHarness {
    function isActive() external view returns (bool) {
        return BaseTimeLib.isActive();
    }

    function timestampMs() external view returns (uint256) {
        return BaseTimeLib.timestampMs();
    }

    function millisPart() external view returns (uint16) {
        return BaseTimeLib.millisPart();
    }
}

/// @dev INTEGRATION CHECKS, not unit tests. They depend on live Base Sepolia state and
/// run only with `--fork-url https://sepolia.base.org` (`make test-fork`). They verify the
/// real predeploy; the unit suites only verify the library against a mock.
contract DenimLiveTest is Test {
    address constant PREDEPLOY = 0x4200000000000000000000000000000000000030;
    LiveHarness h;

    function setUp() public {
        // Fork at latest. Skip cleanly if this is not Base Sepolia.
        if (block.chainid != 84532) vm.skip(true);
        h = new LiveHarness();
    }

    function test_live_predeployAnswersAndIsActive() public view {
        assertGt(PREDEPLOY.code.length, 0, "proxy has no code");
        assertTrue(h.isActive(), "predeploy not active");
    }

    function test_live_timestampMsMatchesHeader() public view {
        // BaseTime exposes 200ms resolution: ms = 1000 * header timestamp + millis part.
        assertEq(h.timestampMs(), block.timestamp * 1000 + h.millisPart());
        assertEq(IBaseTime(PREDEPLOY).timestampMs(), block.timestamp * 1000 + IBaseTime(PREDEPLOY).timestampMillisPart());
    }

    function test_live_millisPartIsOneOfFiveValues() public view {
        uint16 p = h.millisPart();
        assertTrue(p == 0 || p == 200 || p == 400 || p == 600 || p == 800, "invalid millis part");
    }

    /// Two samples taken at two real Sepolia blocks 100 blocks apart (rollFork reads the
    /// predeploy's state at each block), so block numbers and BaseTime values are live data.
    function test_live_oracleRateAcrossRealBlockGap() public {
        uint256 head = block.number;
        vm.createSelectFork(vm.rpcUrl("base_sepolia"), head - 200);
        BlockRateOracle oracle = new BlockRateOracle();
        vm.makePersistent(address(oracle));
        oracle.sample();
        vm.rollFork(head - 100);
        oracle.sample();
        uint256 rate = oracle.blocksPerSecond();
        emit log_named_uint("observed rate (1e6 = 1 block/s)", rate);
        assertEq(oracle.sampleCount(), 2);
        assertGe(rate, 4.5e6);
        assertLe(rate, 5.5e6);
    }
}
