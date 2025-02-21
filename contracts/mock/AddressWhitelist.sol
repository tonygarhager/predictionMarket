// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@uma/core/contracts/common/implementation/AddressWhitelist.sol";

contract MockAddressWhitelist is AddressWhitelist {
    constructor() AddressWhitelist() {}
}