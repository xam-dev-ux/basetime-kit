// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeLib} from "./BaseTimeLib.sol";

/// @notice Measures the real block production rate from onchain samples and
/// converts between block counts and durations. Holds no funds, has no owner.
/// @dev The rate is taken over a trailing window of the most recent samples.
/// Block timestamps have 200ms resolution, so a span of a few seconds is
/// needed for the measurement to be meaningful; `minSampleGapMs` enforces it.
contract BlockRateOracle {
    struct Sample {
        uint64 blockNumber;
        uint64 timestampMs; // full ms timestamp at sampling, 200ms resolution
        uint64 takenAt; // block.timestamp, whole seconds
        address sampler;
    }

    /// @notice Fixed-point precision for the rate. 1e6 = one block per second.
    uint256 public constant RATE_PRECISION = 1e6;

    /// @notice Minimum gap between retained samples.
    uint256 public constant minSampleGapMs = 2_000;

    /// @notice Ring buffer capacity. Oldest samples are overwritten.
    uint256 public constant MAX_SAMPLES = 64;

    /// @notice The rate is computed over at most this many of the newest samples.
    uint256 public constant WINDOW = 10;

    Sample[MAX_SAMPLES] private _ring;

    /// @notice Total samples ever taken. The retained count is min(this, MAX_SAMPLES).
    uint256 public totalSamples;

    event Sampled(uint256 indexed index, uint64 blockNumber, uint64 timestampMs, address indexed sampler);

    error SampledTooSoon(uint256 sinceMs, uint256 requiredMs);
    error InsufficientSamples();
    error PredeployUnavailable();

    /// @notice Record a sample. Permissionless.
    function sample() external {
        if (!BaseTimeLib.isActive()) revert PredeployUnavailable();

        uint64 nowMs = uint64(BaseTimeLib.timestampMs());

        uint256 n = totalSamples;
        if (n > 0) {
            uint64 lastMs = _ring[(n - 1) % MAX_SAMPLES].timestampMs;
            uint256 gap = nowMs > lastMs ? nowMs - lastMs : 0;
            if (gap < minSampleGapMs) revert SampledTooSoon(gap, minSampleGapMs);
        }

        _ring[n % MAX_SAMPLES] = Sample({
            blockNumber: uint64(block.number),
            timestampMs: nowMs,
            takenAt: uint64(block.timestamp),
            sampler: msg.sender
        });
        totalSamples = n + 1;

        emit Sampled(n, uint64(block.number), nowMs, msg.sender);
    }

    /// @notice Observed blocks per second over the trailing window, scaled by
    /// RATE_PRECISION. Post-Denim this reads close to 5e6; pre-Denim, close to 0.5e6.
    function blocksPerSecond() public view returns (uint256) {
        uint256 n = totalSamples;
        if (n < 2) revert InsufficientSamples();
        uint256 span = n < WINDOW ? n : WINDOW;
        Sample memory first = _ring[(n - span) % MAX_SAMPLES];
        Sample memory last = _ring[(n - 1) % MAX_SAMPLES];
        uint256 elapsedMs = last.timestampMs - first.timestampMs;
        if (elapsedMs == 0) revert InsufficientSamples();
        uint256 blocks = last.blockNumber - first.blockNumber;
        return (blocks * 1000 * RATE_PRECISION) / elapsedMs;
    }

    /// @notice How many blocks span the given number of seconds at the observed
    /// rate. Use this instead of a hardcoded block-count constant.
    function blocksFor(uint256 secs) external view returns (uint256) {
        return (secs * blocksPerSecond()) / RATE_PRECISION;
    }

    /// @notice How many seconds a given block count covers at the observed rate.
    function secondsFor(uint256 blocks) external view returns (uint256) {
        uint256 rate = blocksPerSecond();
        if (rate == 0) revert InsufficientSamples();
        return (blocks * RATE_PRECISION) / rate;
    }

    /// @notice Audit helper: a constant written for pre-Denim two-second blocks,
    /// and the wall-clock time it covers now.
    function reinterpret(uint256 legacyBlockCount)
        external
        view
        returns (uint256 intendedSeconds, uint256 actualSeconds)
    {
        uint256 rate = blocksPerSecond();
        if (rate == 0) revert InsufficientSamples();
        intendedSeconds = legacyBlockCount * 2;
        actualSeconds = (legacyBlockCount * RATE_PRECISION) / rate;
    }

    /// @notice Number of samples currently retained.
    function sampleCount() external view returns (uint256) {
        return totalSamples < MAX_SAMPLES ? totalSamples : MAX_SAMPLES;
    }

    /// @notice Retained sample by position, 0 = oldest retained.
    function sampleAt(uint256 i) external view returns (Sample memory) {
        uint256 n = totalSamples;
        uint256 count = n < MAX_SAMPLES ? n : MAX_SAMPLES;
        if (i >= count) revert InsufficientSamples();
        return _ring[(n - count + i) % MAX_SAMPLES];
    }

    function latest() external view returns (Sample memory) {
        if (totalSamples == 0) revert InsufficientSamples();
        return _ring[(totalSamples - 1) % MAX_SAMPLES];
    }
}
