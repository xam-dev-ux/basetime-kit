// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BlockRateOracle} from "../src/BlockRateOracle.sol";
import {MockBaseTime, RevertingBaseTime} from "./mocks/MockBaseTime.sol";

/// @dev Unit tests with the mock plus vm.roll / vm.warp. Not a simulation of the live chain.
contract BlockRateOracleTest is Test {
    address constant PREDEPLOY = 0x4200000000000000000000000000000000000030;
    uint256 constant T0 = 1_800_000_000_000; // ms
    BlockRateOracle oracle;
    MockBaseTime mock;

    function setUp() public {
        vm.etch(PREDEPLOY, address(new MockBaseTime()).code);
        mock = MockBaseTime(PREDEPLOY);
        oracle = new BlockRateOracle();
        vm.roll(1000);
    }

    function _sampleAt(uint256 blockNo, uint256 ms) internal {
        vm.roll(blockNo);
        vm.warp(ms / 1000);
        mock.setTimestampMs(ms);
        oracle.sample();
    }

    /// two samples `dtMs` and `dBlocks` apart
    function _pair(uint256 dtMs, uint256 dBlocks) internal {
        _sampleAt(1000, T0);
        _sampleAt(1000 + dBlocks, T0 + dtMs);
    }

    function test_denimRate_fivePerSecond() public {
        _pair(2000, 10);
        assertEq(oracle.blocksPerSecond(), 5e6);
    }

    function test_preDenimRate_halfPerSecond() public {
        _pair(2000, 1);
        assertEq(oracle.blocksPerSecond(), 0.5e6);
    }

    function test_blocksFor_sevenDays() public {
        _pair(2000, 10);
        assertEq(oracle.blocksFor(7 days), 3_024_000);
    }

    function test_secondsFor_legacyConstant() public {
        _pair(2000, 10);
        assertEq(oracle.secondsFor(302_400), 60_480);
    }

    function test_reinterpret_legacyConstant() public {
        _pair(2000, 10);
        (uint256 intended, uint256 actual) = oracle.reinterpret(302_400);
        assertEq(intended, 604_800);
        assertEq(actual, 60_480);
    }

    function test_sample_revertsTooSoon() public {
        _sampleAt(1000, T0);
        vm.roll(1001);
        mock.setTimestampMs(T0 + 1800);
        vm.expectRevert(abi.encodeWithSelector(BlockRateOracle.SampledTooSoon.selector, 1800, 2000));
        oracle.sample();
    }

    function test_sample_allowedAtExactGap() public {
        _sampleAt(1000, T0);
        _sampleAt(1010, T0 + 2000);
        assertEq(oracle.sampleCount(), 2);
    }

    function test_blocksPerSecond_revertsWithFewerThanTwo() public {
        vm.expectRevert(BlockRateOracle.InsufficientSamples.selector);
        oracle.blocksPerSecond();
        _sampleAt(1000, T0);
        vm.expectRevert(BlockRateOracle.InsufficientSamples.selector);
        oracle.blocksPerSecond();
    }

    function test_sample_revertsWhenPredeployInactive() public {
        vm.etch(PREDEPLOY, address(new RevertingBaseTime()).code);
        vm.expectRevert(BlockRateOracle.PredeployUnavailable.selector);
        oracle.sample();
        vm.etch(PREDEPLOY, "");
        vm.expectRevert(BlockRateOracle.PredeployUnavailable.selector);
        oracle.sample();
    }

    function testFuzz_sample_permissionless(address caller) public {
        vm.assume(caller != address(0));
        vm.prank(caller);
        oracle.sample();
        assertEq(oracle.latest().sampler, caller);
    }

    // --- division safety -------------------------------------------------

    function test_zeroElapsed_reverts() public {
        _sampleAt(1000, T0);
        // force a second sample at the same ms by lowering the gap check: not reachable
        // through sample(), so a zero-elapsed pair cannot be stored. Assert the guard instead.
        vm.roll(1010);
        mock.setTimestampMs(T0);
        vm.expectRevert(abi.encodeWithSelector(BlockRateOracle.SampledTooSoon.selector, 0, 2000));
        oracle.sample();
    }

    function test_zeroRate_secondsForAndReinterpretRevert() public {
        _pair(2000, 0); // no blocks between samples -> rate 0
        assertEq(oracle.blocksPerSecond(), 0);
        vm.expectRevert(BlockRateOracle.InsufficientSamples.selector);
        oracle.secondsFor(100);
        vm.expectRevert(BlockRateOracle.InsufficientSamples.selector);
        oracle.reinterpret(100);
        assertEq(oracle.blocksFor(1000), 0);
    }

    function test_veryLargeBlockCount() public {
        _pair(2000, 10);
        assertEq(oracle.secondsFor(type(uint128).max), (uint256(type(uint128).max) * 1e6) / 5e6);
        vm.expectRevert(); // overflow in blocks * RATE_PRECISION
        oracle.secondsFor(type(uint256).max);
    }

    // --- ring buffer and window -------------------------------------------

    function test_ringBuffer_evictsOldest() public {
        uint256 total = oracle.MAX_SAMPLES() + 6;
        for (uint256 i = 0; i < total; i++) {
            _sampleAt(1000 + i * 10, T0 + i * 2000);
        }
        assertEq(oracle.totalSamples(), total);
        assertEq(oracle.sampleCount(), oracle.MAX_SAMPLES());
        assertEq(oracle.sampleAt(0).blockNumber, 1000 + 6 * 10);
        assertEq(oracle.latest().blockNumber, 1000 + (total - 1) * 10);
        assertEq(oracle.blocksPerSecond(), 5e6);
    }

    function test_window_usesTrailingSamplesOnly() public {
        // 20 old samples at 1 block/2s, then 10 at 5 blocks/s: window should read 5e6
        uint256 b = 1000;
        uint256 t = T0;
        for (uint256 i = 0; i < 20; i++) {
            _sampleAt(b, t);
            b += 1;
            t += 2000;
        }
        for (uint256 i = 0; i < 10; i++) {
            _sampleAt(b, t);
            b += 10;
            t += 2000;
        }
        assertEq(oracle.blocksPerSecond(), 5e6);
    }
}
