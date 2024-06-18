// SPDX-License-Identifier: MIT
// For the RaffleTest.t.sol unit test

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 entranceFee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane, // gasLane = keyHash
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link
        ) = helperConfig.activeNetworkConfig();

        // 1.
        // we need a subscriptionId to deploy the raffle if we don't have one
        // We create it and then fund it
        if (subscriptionId == 0) {
            // we are going to need to create a subscription!
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(vrfCoordinator);

            // After creating the subscription we now need to fund it
            // Fund it!
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(vrfCoordinator, subscriptionId, link);
        }

        // 2.
        // Then we launch/Deploy our raffle
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane, // gasLane = keyHash
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();

        // Since its a brand new raffle we need to
        // Add the raffle to a list of consumers in the subscription management
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(raffle), vrfCoordinator, subscriptionId);
        return (raffle, helperConfig);
    }
}

// WE DID ALL THIS SO WE CAN GO BACK TO OUR RaffleTest.t.sol unit test
