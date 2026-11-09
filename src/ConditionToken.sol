// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title CONDITIONALS (CONDITION)
/// @notice Fixed-supply ERC-20. The deploying account receives the entire supply once.
/// @dev The launch factory is msg.sender when it deploys this contract. There are no admin powers.
contract ConditionToken is ERC20 {
    /// @notice One billion tokens expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("CONDITIONALS", "CONDITION") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
