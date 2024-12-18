// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";

// Mock USDT contract
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT", 6) {} // USDT has 6 decimals

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
