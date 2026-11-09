// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ConditionToken} from "../src/ConditionToken.sol";

/// @dev Exercises arbitrary sequences of holder and spender operations over a closed actor set.
contract TokenHandler is Test {
    ConditionToken private immutable token;
    address[4] private actors;

    constructor(ConditionToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, beforeFrom);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), beforeFrom);
        } else {
            assertEq(token.balanceOf(from), beforeFrom - amount);
            assertEq(token.balanceOf(to), beforeTo + amount);
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.INITIAL_SUPPLY() + 1);
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        uint256 approved = token.allowance(from, spender);
        bool shouldSucceed = amount <= beforeFrom && amount <= approved;
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool success) {
            assertTrue(success);
            assertTrue(shouldSucceed, "unauthorized or overdrawn transfer succeeded");
            uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
            assertEq(token.allowance(from, spender), remaining);
            if (from == to) {
                assertEq(token.balanceOf(from), beforeFrom);
            } else {
                assertEq(token.balanceOf(from), beforeFrom - amount);
                assertEq(token.balanceOf(to), beforeTo + amount);
            }
        } catch {
            assertFalse(shouldSucceed, "valid transfer reverted");
            assertEq(token.allowance(from, spender), approved);
            assertEq(token.balanceOf(from), beforeFrom);
            assertEq(token.balanceOf(to), beforeTo);
        }
    }
}

contract ConditionTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionToken private token;
    TokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new ConditionToken();
        actors = [makeAddr("holder0"), makeAddr("holder1"), makeAddr("holder2"), makeAddr("holder3")];
        for (uint256 i; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        handler = new TokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            balances += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "CONDITIONALS");
        assertEq(token.symbol(), "CONDITION");
        assertEq(token.decimals(), 18);
    }
}
