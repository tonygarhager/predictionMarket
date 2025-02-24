// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

//import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/contracts/optimistic-oracle-v2/interfaces/OptimisticOracleV2Interface.sol";

import { AncillaryDataLib } from "./libraries/AncillaryDataLib.sol";
import { Auth } from "./libraries/Auth.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ERC20 } from "./libraries/ERC20.sol";


/**
 * @title Optimistic Requester.
 * @notice Optional interface that requesters can implement to receive callbacks.
 * @dev this contract does _not_ work with ERC777 collateral currencies or any others that call into the receiver on
 * transfer(). Using an ERC777 token would allow a user to maliciously grief other participants (while also losing
 * money themselves).
 */
interface OptimisticRequester {
    /**
     * @notice Callback for proposals.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     */
    function priceProposed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData
    ) external;

    /**
     * @notice Callback for disputes.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     * @param refund refund received in the case that refundOnDispute was enabled.
     */
    function priceDisputed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        uint256 refund
    ) external;

    /**
     * @notice Callback for settlement.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     * @param price price that was resolved by the escalation process.
     */
    function priceSettled(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        int256 price
    ) external;
}

// This contract allows to initialize prediction markets each having a pair of binary outcome tokens. Anyone can mint
// and burn the same amount of paired outcome tokens for the default payout currency. Trading of outcome tokens is
// outside the scope of this contract. Anyone can assert 3 possible outcomes (outcome 1, outcome 2 or split) that is
// verified through Optimistic Oracle V3. If the assertion is resolved true then holders of outcome tokens can settle
// them for the payout currency based on resolved market outcome.
contract PredictionMarket is Auth, OptimisticRequester {
    //using SafeERC20 for IERC20;

    //errors
    error InvalidAncillaryData();
    error NotInitialized();
    error Paused();
    error Resolved();
    error NotReadyToResolve();
    error InvalidOOPrice();

    struct Market {
        bool resolved;              // Flag marking whether a market is resolved
        bool paused;                // Flag marking whether a market is paused
        bool reset;                 // Flag marking whether a market has been reset. A market can only be reset once
        int256 assertedOutcomeId;    // Index of asserted outcome (1: outcome1, 2: outcome2, 3: unresolvable).
        bytes32 assertionId;        // Hash of assertion from oo.
        uint256 reward;             // Reward available for asserting true market outcome.
        uint256 requiredBond;       // Expected bond to assert market outcome 
        bytes outcome1;             // Short name of the first outcome.
        bytes outcome2;             // Short name of the second outcome.
        bytes description;          // Description of the market.
        uint256 requestTimestamp;   // Used to identify the request and NOT used by the DVM to determine validity
    }

    struct AssertedMarket {
        address asserter; // Address of the asserter used for reward payout.
        bytes32 marketId; // Identifier for markets mapping.
    }

    mapping(bytes32 => Market) public markets; // Maps marketId to Market struct.

    mapping(bytes32 => AssertedMarket) public assertedMarkets; // Maps assertionId to AssertedMarket.

    ERC20 public immutable currency; // Currency used for all prediction markets.
    OptimisticOracleV2Interface public immutable oo;
    //uint64 public constant assertionLiveness = 120; // 2 hours.
    uint256 public constant maxAncillaryData = 8139;
    //bytes32 public constant defaultIdentifier = 0x4153534552545f54525554480000000000000000000000000000000000000000; // Identifier used for all prediction markets.
    
    /// @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant yesOrNoIdentifier = "YES_OR_NO_QUERY";

    bytes public constant unresolvable = "Unresolvable"; // Name of the unresolvable outcome where payouts are split.
    mapping(address => bool) private verifiers;

    event MarketInitialized(bytes32 indexed marketId, string outcome1, string outcome2, string description, uint256 reward, uint256 requiredBond);
    event MarketAsserted(bytes32 identifier, uint256 timestamp, bytes ancillaryData);
    event MarketDisputed(bytes32 identifier, uint256 timestamp, bytes ancillaryData, uint256 refund);
    event MarketResultSettled(bytes32 identifier, uint256 timestamp, bytes ancillaryData, int256 price);
    event MarketResolved(bytes32 indexed marketId, int256 price, uint256[] payouts);
    event MarketPaused(bytes32 indexed marketId);
    event MarketUnpaused(bytes32 indexed marketId);
    event MarketReset(bytes32 indexed marketId);

    constructor(
        address _currency,
        address _optimisticOracleV2
    ) {
        currency = ERC20(_currency);
        oo = OptimisticOracleV2Interface(_optimisticOracleV2);
    }

    /* unused
    function getMarket(bytes32 marketId) public view returns (Market memory) {
        return markets[marketId];
    }
    */

    function createMarket(
        bytes32 marketId,
        string memory outcome1,     // Short name of the first outcome.
        string memory outcome2,     // Short name of the second outcome.
        string memory description,  // Description of the market.
        uint256 reward,             // Reward available for asserting true market outcome.
        uint256 requiredBond,       // Expected bond to assert market outcome (OOv3 can require higher bond).
        uint256 assertionLiveness    // Market live during assertionLiveness
    ) public {
        require(markets[marketId].description.length == 0, "Market exists");
        require(bytes(outcome1).length > 0, "Empty first outcome");
        require(bytes(outcome2).length > 0, "Empty second outcome");
        require(keccak256(bytes(outcome1)) != keccak256(bytes(outcome2)), "Outcomes are the same");
        require(bytes(description).length > 0, "Empty description");

        bytes memory byDesc = bytes(description);

        bytes memory data = AncillaryDataLib._appendAncillaryData(msg.sender, byDesc);
        if (byDesc.length == 0 || data.length > maxAncillaryData) revert InvalidAncillaryData();
        
        uint256 timestamp = block.timestamp;

        markets[marketId] = Market({
            resolved: false,
            paused: false,
            reset: false,
            assertedOutcomeId: 0,
            assertionId: bytes32(0),
            reward: reward,
            requiredBond: requiredBond,
            outcome1: bytes(outcome1),
            outcome2: bytes(outcome2),
            description: data,
            requestTimestamp: timestamp
        });
        _requestPrice(msg.sender, timestamp, data, address(currency), reward, requiredBond);
        oo.setCustomLiveness(yesOrNoIdentifier, timestamp, data, assertionLiveness);
        emit MarketInitialized(marketId, outcome1, outcome2, description, reward, requiredBond);
    }

    
    function assertMarket(bytes32 marketId, string memory assertedOutcome) public {
        Market storage market = markets[marketId];
        require(market.assertedOutcomeId == 0, "Assertion active or resolved");
        bytes32 assertedOutcomeHash = keccak256(bytes(assertedOutcome));
        int256 assertedOutcomeId = 0;
        if (assertedOutcomeHash == keccak256(market.outcome1))
            assertedOutcomeId = 1;
        else if (assertedOutcomeHash == keccak256(market.outcome2))
            assertedOutcomeId = 2;
        else if (assertedOutcomeHash == keccak256(unresolvable))
            assertedOutcomeId = 3;
        else
            revert("Invalid asserted outcome");

        market.assertedOutcomeId = assertedOutcomeId;
        //OOv2 has not minimum bond
        uint256 bond = market.requiredBond;
        
        // Pull bond and make the assertion.
        TransferHelper._transferFromERC20(address(currency), msg.sender, address(this), bond);
        if (IERC20(address(currency)).allowance(address(this), address(oo)) < bond) {
            IERC20(address(currency)).approve(address(oo), type(uint256).max);
        }
        //currency.safeTransferFrom(msg.sender, address(this), bond);
        //currency.safeApprove(address(oo), bond);
        oo.proposePriceFor(msg.sender, address(this), yesOrNoIdentifier, market.requestTimestamp, market.description, market.assertedOutcomeId);
       
        // Store the asserter and marketId for the assertionResolvedCallback.
        assertedMarkets[market.assertionId] = AssertedMarket({ asserter: msg.sender, marketId: marketId });
    }

    /// @notice Checks whether a marketId is ready to be resolved
    /// @param marketId - The unique marketId
    function ready(bytes32 marketId) public view returns (bool) {
        return _ready(markets[marketId]);
    }


    /// @notice Resolves a market
    /// Pulls price information from the OO and resolves the underlying CTF market.
    /// Reverts if price is not available on the OO
    /// Resets the question if the price returned by the OO is the Ignore price
    /// @param marketId - The unique marketId of the market
    function resolve(bytes32 marketId) external {
        Market storage market = markets[marketId];

        if (!_isInitialized(market)) revert NotInitialized();
        if (market.paused) revert Paused();
        if (market.resolved) revert Resolved();
        if (!_hasPrice(market)) revert NotReadyToResolve();

        // Resolve the underlying market
        return _resolve(marketId, market);
    }

    
    function disputeMarket(bytes32 marketId) public {
        Market storage market = markets[marketId];
        require(market.assertedOutcomeId > 0, "Assertion not proposed");

        if (market.reset) return;

        // If the market has not been reset previously, reset the market
        // Ensures that there are at most 2 OO Requests at a time for a market
        //_reset(address(this), marketId, market);
        oo.disputePriceFor(msg.sender, address(this), yesOrNoIdentifier, market.requestTimestamp, market.description);
    }

    /// @notice Checks if a market is initialized
    /// @param marketId - The unique marketId
    function isInitialized(bytes32 marketId) public view returns (bool) {
        return _isInitialized(markets[marketId]);
    }

    
    /*////////////////////////////////////////////////////////////////////
                            ADMIN ONLY FUNCTIONS 
    ///////////////////////////////////////////////////////////////////*/

    /// @notice Allows an admin to reset a market, sending out a new price request to the OO.
    /// Failsafe to be used if the priceDisputed callback reverts during execution.
    /// @param marketId - The unique marketId
    /*
    function reset(bytes32 marketId) external onlyAdmin {
        Market storage market = markets[marketId];
        if (!_isInitialized(market)) revert NotInitialized();
        if (market.resolved) revert Resolved();

        // Reset the market, paying for the price request from the caller
        _reset(msg.sender, marketId, market);
    }
    */
    
    /// @notice Allows an admin to pause market resolution in an emergency
    /// @param marketId - The unique marketId of the market
    function pause(bytes32 marketId) external onlyAdmin {
        Market storage market = markets[marketId];

        if (!_isInitialized(market)) revert NotInitialized();

        market.paused = true;
        emit MarketPaused(marketId);
    }

    /// @notice Allows an admin to unpause market resolution in an emergency
    /// @param marketId - The unique marketId of the market
    function unpause(bytes32 marketId) external onlyAdmin {
        Market storage market = markets[marketId];
        if (!_isInitialized(market)) revert NotInitialized();

        market.paused = false;
        emit MarketUnpaused(marketId);
    }

    /*///////////////////////////////////////////////////////////////////
                            CALLBACK FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback for proposals.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     */
    function priceProposed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData
    ) external {
        emit MarketAsserted(identifier, timestamp, ancillaryData);
    }

    /**
     * @notice Callback for disputes.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     * @param refund refund received in the case that refundOnDispute was enabled.
     */
    function priceDisputed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        uint256 refund
    ) external {
        emit MarketDisputed(identifier, timestamp, ancillaryData, refund);
    }

    /**
     * @notice Callback for settlement.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data of the price being requested.
     * @param price price that was resolved by the escalation process.
     */
    function priceSettled(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        int256 price
    ) external {
        emit MarketResultSettled(identifier, timestamp, ancillaryData, price);
    }
    
    /*
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
    */
    // Dispute callback does nothing.
    //function assertionDisputedCallback(bytes32 assertionId) public {}
    /*
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
    */
    /*///////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    function _ignorePrice() internal pure returns (int256) {
        return type(int256).min;
    }
    
    /// @notice Resolves the market
    /// @param marketId   - The unique marketId of the market
    /// @param market - The market data parameters
    function _resolve(bytes32 marketId, Market storage market) internal {
        // Get the price from the OO
        int256 price = oo.settleAndGetPrice(
            yesOrNoIdentifier, market.requestTimestamp, market.description
        );

        // If the OO returns the ignore price, reset the question
        if (price == _ignorePrice()) return _reset(address(this), marketId, market);

        // Construct the payout array for the question
        uint256[] memory payouts = _constructPayouts(price);

        // Set resolved flag
        market.resolved = true;

        emit MarketResolved(marketId, price, payouts);
    }

    /// @notice Construct the payout array given the price
    /// @param price - The price retrieved from the OO
    function _constructPayouts(int256 price) internal pure returns (uint256[] memory) {
        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);
        // Valid prices are 0, 0.5 and 1
        if (price != 0 && price != 0.5 ether && price != 1 ether) revert InvalidOOPrice();

        if (price == 0) {
            // NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (price == 0.5 ether) {
            // UNKNOWN: Report [Yes, No] as [1, 1], 50/50
            payouts[0] = 1;
            payouts[1] = 1;
        } else {
            // YES: Report [Yes, No] as [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }
        return payouts;
    }

    /// @notice Reset the market by updating the requestTimestamp field and sending a new price request to the OO
    /// @param marketId - The unique marketId
    function _reset(address requestor, bytes32 marketId, Market storage market) internal {
        uint256 requestTimestamp = block.timestamp;
        // Update the question parameters in storage
        market.requestTimestamp = requestTimestamp;
        market.reset = true;

        // Send out a new price request with the new timestamp
        _requestPrice(
            requestor,
            requestTimestamp,
            market.description,
            address(currency),
            market.reward,
            market.requiredBond
        );

        emit MarketReset(marketId);
    }

    function _hasPrice(Market storage market) internal view returns (bool) {
        return oo.hasPrice(
            address(this), yesOrNoIdentifier, market.requestTimestamp, market.description
        );
    }

    function _ready(Market storage market) internal view returns (bool) {
        if (!_isInitialized(market)) return false;
        if (market.paused) return false;
        if (market.resolved) return false;
        return _hasPrice(market);
    }
    
    function _isInitialized(Market storage market) internal view returns (bool) {
        return market.description.length > 0;
    }

    /// @notice Request a price from the Optimistic Oracle
    /// Transfers reward token from the requestor if non-zero reward is specified
    /// @param requestor        - Address of the requestor
    /// @param requestTimestamp - Timestamp used in the OO request
    /// @param ancillaryData    - Data used to resolve a question
    /// @param rewardToken      - Address of the reward token
    /// @param reward           - Reward amount, denominated in rewardToken
    /// @param bond             - Bond amount used, denominated in rewardToken
    function _requestPrice(
        address requestor,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        //if (reward > 0) currency.safeTransferFrom(requestor, address(this), reward); // Pull reward.
        if (reward > 0) {
            // If the requestor is not the Adapter, the requestor pays for the price request
            // If not, the Adapter pays for the price request
            if (requestor != address(this)) {
                TransferHelper._transferFromERC20(rewardToken, requestor, address(this), reward);
            }

            // Approve the OO as spender on the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(oo)) < reward) {
                IERC20(rewardToken).approve(address(oo), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        oo.requestPrice(yesOrNoIdentifier, requestTimestamp, ancillaryData, IERC20(rewardToken), reward);

        // Ensure the price request is event based
        oo.setEventBased(yesOrNoIdentifier, requestTimestamp, ancillaryData);

        // Ensure that the dispute callback flag is set
        oo.setCallbacks(
            yesOrNoIdentifier,
            requestTimestamp,
            ancillaryData,
            true, // DO NOT set callback on priceProposed
            true, // DO set callback on priceDisputed
            true // DO NOT set callback on priceSettled
        );

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) oo.setBond(yesOrNoIdentifier, requestTimestamp, ancillaryData, bond);
    }
}