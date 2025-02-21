// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";

// This contract allows to initialize prediction markets each having a pair of binary outcome tokens. Anyone can mint
// and burn the same amount of paired outcome tokens for the default payout currency. Trading of outcome tokens is
// outside the scope of this contract. Anyone can assert 3 possible outcomes (outcome 1, outcome 2 or split) that is
// verified through Optimistic Oracle V3. If the assertion is resolved true then holders of outcome tokens can settle
// them for the payout currency based on resolved market outcome.
contract PredictionMarket is OptimisticOracleV3CallbackRecipientInterface {
    using SafeERC20 for IERC20;

    struct Market {
        bool resolved; // True if the market has been resolved and payouts can be settled.
        uint8 assertedOutcomeId; // Index of asserted outcome (1: outcome1, 2: outcome2, 3: unresolvable).
        bytes32 assertionId; // Hash of assertion from oo.
        uint256 reward; // Reward available for asserting true market outcome.
        uint256 requiredBond; // Expected bond to assert market outcome (OOv3 can require higher bond).
        bytes outcome1; // Short name of the first outcome.
        bytes outcome2; // Short name of the second outcome.
        bytes description; // Description of the market.
    }

    struct AssertedMarket {
        address asserter; // Address of the asserter used for reward payout.
        bytes32 marketId; // Identifier for markets mapping.
    }

    mapping(bytes32 => Market) public markets; // Maps marketId to Market struct.

    mapping(bytes32 => AssertedMarket) public assertedMarkets; // Maps assertionId to AssertedMarket.

    IERC20 public immutable currency; // Currency used for all prediction markets.
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 120; // 2 hours.
    bytes32 public constant defaultIdentifier = 0x4153534552545f54525554480000000000000000000000000000000000000000; // Identifier used for all prediction markets.
    bytes public constant unresolvable = "Unresolvable"; // Name of the unresolvable outcome where payouts are split.
    mapping(address => bool) private verifiers;

    event MarketInitialized(
        bytes32 indexed marketId,
        string outcome1,
        string outcome2,
        string description,
        uint256 reward,
        uint256 requiredBond
    );
    event MarketAsserted(bytes32 indexed marketId, bytes32 indexed assertionId);
    event MarketDisputed(bytes32 indexed marketId, bytes32 indexed assertionId);
    event MarketResolved(bytes32 indexed marketId);

    constructor(
        address _currency,
        address _optimisticOracleV3
    ) {
        currency = IERC20(_currency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
    }

    function getMarket(bytes32 marketId) public view returns (Market memory) {
        return markets[marketId];
    }

    function createMarket(
        bytes32 marketId,
        string memory outcome1, // Short name of the first outcome.
        string memory outcome2, // Short name of the second outcome.
        string memory description, // Description of the market.
        uint256 reward, // Reward available for asserting true market outcome.
        uint256 requiredBond // Expected bond to assert market outcome (OOv3 can require higher bond).
    ) public {
        require(markets[marketId].description.length == 0, "Market exists");
        require(bytes(outcome1).length > 0, "Empty first outcome");
        require(bytes(outcome2).length > 0, "Empty second outcome");
        require(keccak256(bytes(outcome1)) != keccak256(bytes(outcome2)), "Outcomes are the same");
        require(bytes(description).length > 0, "Empty description");
        
        markets[marketId] = Market({
            resolved: false,
            assertedOutcomeId: 0,
            assertionId: bytes32(0),
            reward: reward,
            requiredBond: requiredBond,
            outcome1: bytes(outcome1),
            outcome2: bytes(outcome2),
            description: bytes(description)
        });
        if (reward > 0) currency.safeTransferFrom(msg.sender, address(this), reward); // Pull reward.
        emit MarketInitialized(
            marketId,
            outcome1,
            outcome2,
            description,
            reward,
            requiredBond
        );
    }

    function assertMarket(bytes32 marketId, string memory assertedOutcome) public {
        Market storage market = markets[marketId];
        require(market.assertedOutcomeId == 0, "Assertion active or resolved");
        bytes32 assertedOutcomeHash = keccak256(bytes(assertedOutcome));
        uint8 assertedOutcomeId = 0;
        if (assertedOutcomeHash == keccak256(market.outcome1))
            assertedOutcomeId = 1;
        else if (assertedOutcomeHash == keccak256(market.outcome2))
            assertedOutcomeId = 2;
        else if (assertedOutcomeHash == keccak256(unresolvable))
            assertedOutcomeId = 3;
        else
            revert("Invalid asserted outcome");

        market.assertedOutcomeId = assertedOutcomeId;
        uint256 minimumBond = oo.getMinimumBond(address(currency)); // OOv3 might require higher bond.
        uint256 bond = market.requiredBond > minimumBond ? market.requiredBond : minimumBond;
        
        bytes memory claim = abi.encodePacked(
            "As of assertion timestamp ",
            ClaimData.toUtf8BytesUint(block.timestamp),
            ", the described prediction market outcome is: ",
            assertedOutcome,
            ". The market description is: ",
            market.description
        );

        // Pull bond and make the assertion.
        currency.safeTransferFrom(msg.sender, address(this), bond);
        currency.safeApprove(address(oo), bond);
        market.assertionId = oo.assertTruth(
            claim,
            msg.sender, // Asserter
            address(this), // Receive callback in this contract.
            address(0), // No sovereign security.
            assertionLiveness,
            currency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        // Store the asserter and marketId for the assertionResolvedCallback.
        assertedMarkets[market.assertionId] = AssertedMarket({ asserter: msg.sender, marketId: marketId });

        emit MarketAsserted(marketId, market.assertionId);
    }

    function disputeMarket(bytes32 marketId) public {
        Market memory market = markets[marketId];
        require(market.assertedOutcomeId > 0, "Assertion not proposed");
        uint256 minimumBond = oo.getMinimumBond(address(currency)); // OOv3 might require higher bond.
        uint256 bond = market.requiredBond > minimumBond ? market.requiredBond : minimumBond;
        currency.safeTransferFrom(msg.sender, address(this), bond);
        currency.safeApprove(address(oo), bond);

        oo.disputeAssertion(market.assertionId, msg.sender);
        emit MarketDisputed(marketId, market.assertionId);
    }

    // Callback from settled assertion.
    // If the assertion was resolved true, then the asserter gets the reward and the market is marked as resolved.
    // Otherwise, assertedOutcomeId is reset and the market can be asserted again.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
        require(msg.sender == address(oo), "Not authorized");
        Market storage market = markets[assertedMarkets[assertionId].marketId];

        if (assertedTruthfully) {
            market.resolved = true;
            if (market.reward > 0) currency.safeTransfer(assertedMarkets[assertionId].asserter, market.reward);
            emit MarketResolved(assertedMarkets[assertionId].marketId);
        } else {
            market.assertedOutcomeId = 0;
            market.assertionId = bytes32(0);
        }
        // delete assertedMarkets[assertionId];
    }

    // Dispute callback does nothing.
    function assertionDisputedCallback(bytes32 assertionId) public {}

    function _composeClaim(string memory outcome, bytes memory description) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                "As of assertion timestamp ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                ", the described prediction market outcome is: ",
                outcome,
                ". The market description is: ",
                description
            );
    }
}