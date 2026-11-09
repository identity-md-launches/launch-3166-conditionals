// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionToken} from "../src/ConditionToken.sol";

/// @dev Drives the token with valid AND invalid calls (overdrafts, zero addresses, missing
/// allowances) and keeps an independent ghost ledger. Every call is wrapped in try/catch so the
/// handler itself never reverts; whether the token reverted is checked against what the ledger
/// says should have happened.
contract ModelHandler is Test {
    ConditionToken public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    /// @dev Total ever granted by owner to spender through approve (saturating) and total the
    /// spender has moved out of owner's account through transferFrom.
    mapping(address => mapping(address => uint256)) public ghostGranted;
    mapping(address => mapping(address => uint256)) public ghostSpent;
    mapping(address => mapping(address => bool)) public ghostEverInfinite;

    uint256 public successes;
    uint256 public expectedFailures;

    constructor(ConditionToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev One in eight recipients is the zero address, which must always be refused.
    function _recipient(uint256 seed) private view returns (address) {
        if (seed % 8 == 7) return address(0);
        return _actor(seed / 8);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 bal = ghostBalance[from];
        // Up to twice the balance (plus one) so overdrafts are exercised regularly.
        amount = bound(amount, 0, bal * 2 + 1);

        bool shouldSucceed = to != address(0) && amount <= bal;
        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            assertTrue(ok, "transfer returned false");
            assertTrue(shouldSucceed, "invalid transfer succeeded");
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++successes;
        } catch (bytes memory reason) {
            assertFalse(shouldSucceed, "valid transfer reverted");
            if (to == address(0)) {
                assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            } else {
                assertEq(
                    reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount)
                );
            }
            ++expectedFailures;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _recipient(spenderSeed);
        if (infinite) amount = type(uint256).max;

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            assertTrue(ok, "approve returned false");
            assertTrue(spender != address(0), "approve to zero spender succeeded");
            ghostAllowance[owner][spender] = amount;
            uint256 granted = ghostGranted[owner][spender];
            ghostGranted[owner][spender] = amount > type(uint256).max - granted ? type(uint256).max : granted + amount;
            if (amount == type(uint256).max) ghostEverInfinite[owner][spender] = true;
            ++successes;
        } catch (bytes memory reason) {
            assertEq(spender, address(0), "valid approve reverted");
            assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            ++expectedFailures;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 bal = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed == type(uint256).max || bal > allowed ? bal : allowed;
        if (cap > 1e30) cap = 1e30;
        amount = bound(amount, 0, cap * 2 + 1);

        bool shouldSucceed = to != address(0) && amount <= bal && amount <= allowed;
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            assertTrue(ok, "transferFrom returned false");
            assertTrue(shouldSucceed, "invalid transferFrom succeeded");
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostSpent[from][spender] += amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++successes;
        } catch (bytes memory reason) {
            assertFalse(shouldSucceed, "valid transferFrom reverted");
            // Allowance is checked first, then the receiver, then the balance.
            if (amount > allowed) {
                assertEq(
                    reason,
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
                );
            } else if (to == address(0)) {
                assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            } else {
                assertEq(
                    reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount)
                );
            }
            ++expectedFailures;
        }
    }

    /// @dev Nobody can mint or burn through any selector: random calldata never changes the supply.
    function randomCall(uint256 callerSeed, bytes calldata data) external {
        address caller = _actor(callerSeed);
        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        // Skip real state-changing ERC-20 selectors; they are modelled above.
        if (
            selector == token.transfer.selector || selector == token.approve.selector
                || selector == token.transferFrom.selector
        ) return;
        uint256 supplyBefore = token.totalSupply();
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        ok;
        assertEq(token.totalSupply(), supplyBefore, "random calldata changed supply");
    }
}

contract ConditionTokenModelInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionToken private token;
    ModelHandler private handler;
    address[] private actors;

    function setUp() public {
        token = new ConditionToken();
        actors.push(address(this)); // the deployer (stands in for the launch factory)
        actors.push(makeAddr("distributor"));
        actors.push(makeAddr("poolManager"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(address(token)); // tokens sent to the token contract itself
        // Uneven start: some actors hold dust, some nothing, the deployer most of it.
        token.transfer(actors[1], SUPPLY / 10);
        token.transfer(actors[2], SUPPLY * 4 / 10);
        token.transfer(actors[3], 1);
        handler = new ModelHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ModelHandler.transfer.selector;
        selectors[1] = ModelHandler.approve.selector;
        selectors[2] = ModelHandler.transferFrom.selector;
        selectors[3] = ModelHandler.randomCall.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_BalancesMatchGhostLedger() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 bal = token.balanceOf(actors[i]);
            assertEq(bal, handler.ghostBalance(actors[i]), "balance diverged from ledger");
            sum += bal;
        }
        assertEq(sum, SUPPLY, "tokens escaped the actor set");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// @dev Guards against a vacuous handler: each path it models really succeeds or really fails.
    function test_HandlerModelsBothOutcomes() public {
        // actor index 0 = deployer, 3 = alice (holds 1 wei), 4 = bob (holds 0), toSeed 7 = zero address.
        handler.transfer(0, 3 * 8, 100); // deployer -> alice, succeeds
        handler.transfer(4, 0, 1); // bob has nothing: overdraft fails
        handler.transfer(0, 7, 1); // to zero address fails
        handler.approve(3, 4 * 8, 50, false); // alice approves bob
        handler.approve(3, 7, 50, false); // zero spender fails
        handler.transferFrom(4, 3, 0, 50); // bob pulls 50 of alice's 101
        handler.transferFrom(4, 3, 0, 1); // allowance exhausted: fails
        assertEq(handler.successes(), 3);
        assertEq(handler.expectedFailures(), 4);
        assertEq(token.balanceOf(actors[3]), 51);
        assertEq(token.allowance(actors[3], actors[4]), 0);
        invariant_BalancesMatchGhostLedger();
        invariant_AllowancesMatchLedgerAndNoSpenderOverspends();
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_TotalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_AllowancesMatchLedgerAndNoSpenderOverspends() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                address owner = actors[i];
                address spender = actors[j];
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender), "allowance diverged");
                if (!handler.ghostEverInfinite(owner, spender)) {
                    assertLe(
                        handler.ghostSpent(owner, spender),
                        handler.ghostGranted(owner, spender),
                        "spender moved more than ever granted"
                    );
                }
            }
            assertEq(token.allowance(actors[i], address(0)), 0, "zero spender has allowance");
        }
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_MetadataIsConstant() public view {
        assertEq(token.name(), "CONDITIONALS");
        assertEq(token.symbol(), "CONDITION");
        assertEq(token.decimals(), 18);
    }
}
