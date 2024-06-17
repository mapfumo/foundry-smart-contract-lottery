// Used Design Pattern => CEI: Checks, Effects, Interactions

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
// forge install smartcontractkit/chainlink-brownie-contracts --no-commit
/**
 * in foundry.tomls
 * remappings = [
 * '@chainlink/contracts/=lib/chainlink-brownie-contracts/contracts/'
 * ]
 */

/**
 * @title A sample Raffle Contract
 * @author Antony Mapfumo
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2 (Verifiable Random Function)
 */
contract Raffle is VRFConsumerBaseV2 {
    // Better than "require"
    // convention is ContractName__FunctionName
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    /* Type Declarations */
    // we don't want anyone entering the raffle whilst we are waiting for
    // the random number to pick a winner
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    /**
     * state variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // all UPPERCASE for const vars
    uint32 private constant NUM_WORDS = 1;
    /**
     * make it immutable to save some gas. \
     * We will only be abble to save it once in the constructor
     */
    uint256 private immutable i_entranceFee;

    // @dev Duration of the lottery in seconds. How long is the lottery running for?
    uint256 private immutable i_interval;
    // VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    /**
     * we can't iterate over a mapping so we are going to use a dynamic array
     * we can't make it immutable to save gas since we we be writing to it as
     * players join the lotery. We will store in in storate
     * since we are going to be paying the "winner" we neeed to make the array "payable"
     */
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane, // gasLane = keyHash
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        /**
         *  Custom errors are more efficient than "require".
         * Try and use them in place of "require"
         *  require(msg.value >= i_entranceFee, "Not enough ETH sent!");
         */
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        /**
         * don't forget "payable" prefix since our array is "payable"
         * payable abblows an address to get "ETH", to be paid
         */
        s_players.push(payable(msg.sender));
        /**
         * Next we need to emit an EVENT about this
         * 1. Events make migration easier
         * 2. Makes front end "indexing" easier
         * 3. As a rule of thumb, each time we update storage we want to emit an event
         */
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev This is the function that the Chainlink Automation nodes call to see
     * if its time to perform an upkeep. The following should be true for the function to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the open state
     * 3. The contract has ETH (aka players)
     * 4. (Implicit) the subscription is funded with LINK
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        // Do checks first, it's gas efficient that way
        // check if enough time has passed
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x0");
    }

    /**
     * 1. Get a random number
     * 2. Use the random number toi pick a player
     * 3. Be automatically called, when enough time (i_interval) has passed
     */
    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        // we don't want anyone to enter the raffle whilst we are choosing a winner
        s_raffleState = RaffleState.CALCULATING;
        // 1. Request the RNG <- ChainLink VRF
        // 2. Get the random number
        //uint256 requestId = i_vrfCoordinator.requestRandomWords(
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit, // max gas we want the callback function to do
            NUM_WORDS // number of random numbers that we want
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256, /*requestId*/ //abi
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN; // open the raffle again

        s_players = new address payable[](0); // new array with initial size zero (0)
        s_lastTimeStamp = block.timestamp; // reset the timer for the new raffle
        emit PickedWinner(winner);

        // Interactions: Finally do external interactions (with other contracts)
        // helps in preventng re-entry attacks

        // pay the winner
        (bool success,) = winner.call{value: address(this).balance}("");
        // check if this payment went through successfully
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * GETTER FUNCTIONS
     */
    /**
     * an "external view" function is a function that can be called from outside
     * the contract and is read-only, meaning it does not modify the contract's state.
     *
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }
}
