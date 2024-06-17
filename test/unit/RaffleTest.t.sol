//spdx-license-identifier: MIT
pragma solidity ^0.8.19;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    // EVENTS

    // We have to redefine events in our tests. A bit anoying but it works
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane; // gasLane = keyHash
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public DEPLOYER = makeAddr("deployer");

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane, // gasLane = keyHash
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE); // give the player some eth //cheat code
    }

    function testRaffleIntializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////////////////////////////////////////////////////////////////////////
    // enterRaffle //
    ////////////////////////////////////////////////////////////////////////////

    function testRaffleRevertsWhenYouDontPayEnouugh() public {
        // Arrange, Act, Assert

        // ARRANGE
        vm.prank(PLAYER);

        // ACT / ASSERT
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        // We are expting this to revert.
        // A successfull call would be a successful test. If it doesn't revert its a failure
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange, Act, Assert
        // ARRANGE
        vm.prank(PLAYER);
        // if (msg.value < i_entranceFee) { revert Raffle__NotEnoughEthSent(); }
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        // ACT / ASSERT
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        // Arrange, Act, Assert
        // ARRANGE
        vm.prank(PLAYER);

        // this one only has one indexed paramater we are setting to true
        // https://book.getfoundry.sh/cheatcodes/expect-emit
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        // Next call the function that emits this event
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        // Arrange, Act, Assert

        // ARRANGE
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        /**
         * Now that we have enetered the raffle we ne need to perform the upkeep (set timer)
         */
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // because we have implemented the Interactions.s.sol script we can call the performUpkeep function
        raffle.performUpkeep("");

        // ACT / ASSERT
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////////////////////////////////////////////////////////////
    //  checkUpKeep                                                           //
    ////////////////////////////////////////////////////////////////////////////

    function testCheckUpkeepReturnsFalseIfIthasNoBalance() public {
        // Arrange, Act, Assert

        // ARRANGE
        vm.warp(block.timestamp + interval + 1); // warp time cheat
        vm.roll(block.number + 1);

        // ACT
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // warp time cheat
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // ACT
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        console.log("upkeepNeeded: ", upkeepNeeded);
        console.log("s_raffleState: ", uint256(raffle.getRaffleState()));

        // ASSERT
        // assert(!upkeepNeeded);
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval); // warp time cheat
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // ACT
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        console.log("upkeepNeeded: ", upkeepNeeded);
        console.log("s_raffleState: ", uint256(raffle.getRaffleState()));

        // ASSERT
        assert(!upkeepNeeded);
    }

    //function testCheckUpkeepReturnsTrueWhenParametersAreGood() public { }

    function testPerformUpkeepCanOnlyRunIfUpkeepNe() public raffleEnteredAndTimePassed {
        // // Arrange

        // ACT / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 s_raffleState = 0;

        // ACT / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpKeepNotNeeded.selector, currentBalance, numPlayers, s_raffleState)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // warp time cheat
        vm.roll(block.number + 1);
        _;
    }

    // What if I need to test using the output of an event?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // this is going to emit the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // to get the Log
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0); // making use the requiestId was actually generated
        assert(rState == Raffle.RaffleState.CALCULATING);
    }

    ////////////////////////////////////////////////////////////////////////////
    //  fulfillRandomWords      // FUZZY TESTING                              //
    ////////////////////////////////////////////////////////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEnteredAndTimePassed
    {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));

        // // check @ 1 & 2 as well just to make sure
        // vm.expectRevert("nonexiistent request");
        // VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(1, address(raffle));

        // vm.expectRevert("nonexiistent request");
        // VRFCoordinatorV2Mock(vrfCoorsdinator).fulfillRandomWords(2, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed {
        // Enter contract, Enter the lottery, perform upkeep, call fulfillRandomWords
        // We will pretend to be the chainlink node for the fulfillRandomWords test on our local test
        
        // Arrange
        uint256 additionEntrants = 5; // only have person who has entered the draw when we started
        uint256 startingIndex = 1;    // because of (raffleEnteredAndTimePassed) so we start at 1
        for (uint256 i = startingIndex; i < startingIndex + additionEntrants; i++) {
            // now we have a whole bunch of people enter the raffle
            address player = address(uint160(i)); // address(1), address(2), etc
            // hoax sets up a prank and gives some ether = prank + deal
            hoax(player, 1 ether); // give our player some 1 eth to enter the raffle with
            // now entering the raffle pretending to be the "player" with 1 ether
            raffle.enterRaffle{value: entranceFee}();
        }

        // pretend to be chainlink VRF to get random number


    }






}
