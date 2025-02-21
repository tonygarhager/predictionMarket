// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@uma/core/contracts/data-verification-mechanism/test/MockOracleAncillary.sol";

contract OracleAncillary is MockOracleAncillary {
    constructor(address _finder) MockOracleAncillary(_finder, address(0)) {} 
}