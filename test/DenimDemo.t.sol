// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DenimDemo} from "../src/DenimDemo.sol";
import {MockBaseTime} from "./mocks/MockBaseTime.sol";

contract DenimDemoTest is Test {
    address constant PREDEPLOY = 0x4200000000000000000000000000000000000030;
    DenimDemo demo;
    MockBaseTime mock;

    function setUp() public {
        vm.etch(PREDEPLOY, address(new MockBaseTime()).code);
        mock = MockBaseTime(PREDEPLOY);
        demo = new DenimDemo();
        vm.warp(1_000_000);
        vm.roll(100);
    }

    function test_recordSlot_countsPerSlot() public {
        for (uint16 i = 0; i < 5; i++) {
            mock.setMillisPart(i * 200);
            vm.roll(block.number + 1);
            demo.recordSlot();
        }
        mock.setMillisPart(400);
        demo.recordSlot();
        uint256[5] memory h = demo.slotHistogram();
        assertEq(h[0], 1);
        assertEq(h[2], 2);
        assertEq(demo.recordCount(), 6);
        assertEq(demo.lastSlot(), 2);
        assertEq(demo.lastTimestampMs(), 1_000_000 * 1000 + 400);
    }

    function test_recordSlot_fallsBackToSlotZeroPreActivation() public {
        vm.etch(PREDEPLOY, "");
        demo.recordSlot();
        assertEq(demo.slotHistogram()[0], 1);
        assertEq(demo.lastTimestampMs(), 1_000_000 * 1000);
    }

    function test_compareClocks_emitsBoth() public {
        mock.setMillisPart(800);
        vm.expectEmit(false, false, false, true);
        emit DenimDemo.ClocksCompared(1_000_000 * 1000, 1_000_000 * 1000 + 800, 800, 100);
        demo.compareClocks();
    }

    function test_blockTimer_firesBeforeTimeTimer() public {
        // written for 60s at 2s/block = 30 blocks; at 5 blocks/s that is 6s
        uint256 id = demo.startTimer(30, 60);
        (bool b, bool t) = demo.isTimerElapsed(id);
        assertFalse(b);
        assertFalse(t);

        vm.roll(block.number + 30);
        vm.warp(block.timestamp + 6);
        (b, t) = demo.isTimerElapsed(id);
        assertTrue(b);
        assertFalse(t);

        vm.expectEmit(true, false, false, false);
        emit DenimDemo.BlockTimerFired(id, 0, 0, 0, 0);
        demo.checkTimer(id);

        // block timer already fired: a second check emits nothing for it
        vm.recordLogs();
        demo.checkTimer(id);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.warp(block.timestamp + 54);
        vm.expectEmit(true, false, false, false);
        emit DenimDemo.TimeTimerFired(id, 0, 0, 0, 0);
        demo.checkTimer(id);
    }

    function test_unknownTimerReverts() public {
        vm.expectRevert(DenimDemo.UnknownTimer.selector);
        demo.checkTimer(0);
        vm.expectRevert(DenimDemo.UnknownTimer.selector);
        demo.isTimerElapsed(7);
    }
}
