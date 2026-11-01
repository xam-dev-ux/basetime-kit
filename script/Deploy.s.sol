// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BaseTimeLib} from "../src/BaseTimeLib.sol";
import {BlockRateOracle} from "../src/BlockRateOracle.sol";
import {DenimDemo} from "../src/DenimDemo.sol";

/// @dev Run with `--account speedrun`; the keystore password is entered interactively.
contract Deploy is Script {
    address constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;

    function run() external {
        require(block.chainid == 84532, "Base Sepolia only");
        require(BaseTimeLib.isActive(), "BaseTime predeploy not active on this chain");

        vm.startBroadcast(DEPLOYER);
        BlockRateOracle oracle = new BlockRateOracle();
        DenimDemo demo = new DenimDemo();
        vm.stopBroadcast();

        uint256 ms = BaseTimeLib.timestampMs();
        console.log("BlockRateOracle:", address(oracle));
        console.log("DenimDemo:      ", address(demo));
        console.log("timestampMs at deployment:", ms);

        string memory k = "deploy";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeAddress(k, "deployer", DEPLOYER);
        vm.serializeAddress(k, "oracle", address(oracle));
        vm.serializeAddress(k, "demo", address(demo));
        vm.serializeUint(k, "blockSeenBySimulation", block.number);
        string memory out = vm.serializeUint(k, "timestampMsSeenBySimulation", ms);
        vm.writeJson(out, ".deployments/sepolia.json");
    }
}
