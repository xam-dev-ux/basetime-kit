// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeLib} from "./BaseTimeLib.sol";

/// @notice Leaves verifiable onchain evidence of what Denim changed. Holds no
/// funds, has no owner. Slot occupancy is in 200ms steps, five per second.
contract DenimDemo {
    struct Timer {
        address owner;
        uint64 startBlock;
        uint64 startTime; // block.timestamp, seconds
        uint64 startMs; // BaseTimeLib.timestampMs() at start
        uint64 blockTarget; // startBlock + N
        uint64 timeTarget; // startTime + S
        bool blockFired;
        bool timeFired;
    }

    uint256[5] private _slotCounts;
    uint256 public recordCount;
    uint8 public lastSlot;
    uint256 public lastTimestampMs;

    Timer[] public timers;

    event SlotRecorded(uint256 indexed index, address indexed caller, uint8 slot, uint256 timestampMs, uint256 blockNumber);
    event ClocksCompared(uint256 blockTimestampTimes1000, uint256 timestampMs, uint16 millisPart, uint256 blockNumber);
    event TimerStarted(
        uint256 indexed id,
        address indexed owner,
        uint64 startBlock,
        uint64 startTime,
        uint64 startMs,
        uint64 blockTarget,
        uint64 timeTarget
    );
    /// @dev Emitted once, by whichever transaction first observes the block-count timer elapsed.
    event BlockTimerFired(uint256 indexed id, uint256 blockNumber, uint256 blockTimestamp, uint256 timestampMs, uint256 elapsedSeconds);
    /// @dev Emitted once, by whichever transaction first observes the timestamp timer elapsed.
    event TimeTimerFired(uint256 indexed id, uint256 blockNumber, uint256 blockTimestamp, uint256 timestampMs, uint256 elapsedSeconds);

    error UnknownTimer();

    /// @notice Record which 200ms slot this block occupies.
    function recordSlot() external {
        uint8 slot = BaseTimeLib.slotIndex();
        uint256 ms = BaseTimeLib.timestampMs();
        _slotCounts[slot]++;
        lastSlot = slot;
        lastTimestampMs = ms;
        emit SlotRecorded(recordCount++, msg.sender, slot, ms, block.number);
    }

    /// @notice Emit whole-second time and BaseTime side by side.
    function compareClocks() external {
        emit ClocksCompared(block.timestamp * 1000, BaseTimeLib.timestampMs(), BaseTimeLib.millisPart(), block.number);
    }

    /// @notice How many recorded calls landed in each of the five slots.
    function slotHistogram() external view returns (uint256[5] memory) {
        return _slotCounts;
    }

    /// @notice Start a pair of timers that were meant to measure the same duration:
    /// one in blocks (`block.number + blocks_`), one in seconds (`block.timestamp + secs`).
    /// With 2-second blocks, `blocks_ = secs / 2` matched. With 200ms blocks the
    /// block timer elapses ten times sooner.
    function startTimer(uint64 blocks_, uint64 secs) external returns (uint256 id) {
        id = timers.length;
        uint64 ms = uint64(BaseTimeLib.timestampMs());
        timers.push(
            Timer({
                owner: msg.sender,
                startBlock: uint64(block.number),
                startTime: uint64(block.timestamp),
                startMs: ms,
                blockTarget: uint64(block.number) + blocks_,
                timeTarget: uint64(block.timestamp) + secs,
                blockFired: false,
                timeFired: false
            })
        );
        emit TimerStarted(id, msg.sender, uint64(block.number), uint64(block.timestamp), ms, timers[id].blockTarget, timers[id].timeTarget);
    }

    function isBlockTimerElapsed(uint256 id) public view returns (bool) {
        if (id >= timers.length) revert UnknownTimer();
        return block.number >= timers[id].blockTarget;
    }

    function isTimeTimerElapsed(uint256 id) public view returns (bool) {
        if (id >= timers.length) revert UnknownTimer();
        return block.timestamp >= timers[id].timeTarget;
    }

    function isTimerElapsed(uint256 id) external view returns (bool blockElapsed, bool timeElapsed) {
        return (isBlockTimerElapsed(id), isTimeTimerElapsed(id));
    }

    /// @notice Permissionless. Emits each timer's firing event the first time the
    /// timer is observed elapsed. Does nothing for a timer that has not elapsed.
    function checkTimer(uint256 id) external {
        if (id >= timers.length) revert UnknownTimer();
        Timer storage t = timers[id];
        uint256 ms = BaseTimeLib.timestampMs();
        if (!t.blockFired && block.number >= t.blockTarget) {
            t.blockFired = true;
            emit BlockTimerFired(id, block.number, block.timestamp, ms, block.timestamp - t.startTime);
        }
        if (!t.timeFired && block.timestamp >= t.timeTarget) {
            t.timeFired = true;
            emit TimeTimerFired(id, block.number, block.timestamp, ms, block.timestamp - t.startTime);
        }
    }

    function timerCount() external view returns (uint256) {
        return timers.length;
    }
}
