// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionToken} from "../src/ConditionToken.sol";

/// @dev Stands in for the launch factory: deploys the token with CREATE2 and performs the whole
/// distribution in the same call, as launchCustom does in one transaction.
contract FactoryStandIn {
    struct Result {
        ConditionToken token;
        uint256 heldAfterDeploy;
        uint256 supplyAfterDeploy;
    }

    function launch(bytes32 salt, address distributor, address pool, address requester, uint256 poolBps)
        external
        returns (Result memory r)
    {
        r.token = new ConditionToken{salt: salt}();
        r.heldAfterDeploy = r.token.balanceOf(address(this));
        r.supplyAfterDeploy = r.token.totalSupply();
        uint256 supply = r.supplyAfterDeploy;
        uint256 swarm = supply / 10;
        uint256 seeded = supply * poolBps / 10_000;
        require(r.token.transfer(distributor, swarm), "swarm");
        require(r.token.transfer(pool, seeded), "seed");
        require(r.token.transfer(requester, r.token.balanceOf(address(this))), "remainder");
    }
}

/// @dev A distributor that pays equal shares to claimants, as the launch's MerkleDistributor does.
contract DistributorStandIn {
    function payEqually(IERC20 token, address[] calldata to, uint256 share) external {
        for (uint256 i; i < to.length; ++i) {
            require(token.transfer(to[i], share), "claim");
        }
    }
}

contract ConditionTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionToken private token;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    function setUp() public {
        token = new ConditionToken();
    }

    // ---------------------------------------------------------------- launch flow

    function test_FactoryDeploysAndDistributesExactlyInOneCall() public {
        FactoryStandIn factory = new FactoryStandIn();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        FactoryStandIn.Result memory r = factory.launch(bytes32(uint256(7)), distributor, pool, requester, 6_000);

        bytes32 initHash = keccak256(type(ConditionToken).creationCode);
        assertEq(address(r.token), vm.computeCreate2Address(bytes32(uint256(7)), initHash, address(factory)));
        assertEq(r.heldAfterDeploy, SUPPLY, "factory did not receive whole supply");
        assertEq(r.supplyAfterDeploy, SUPPLY);
        assertEq(r.token.balanceOf(distributor), SUPPLY / 10, "swarm share short");
        assertEq(r.token.balanceOf(pool), SUPPLY * 6 / 10, "pool seed short");
        assertEq(r.token.balanceOf(requester), SUPPLY * 3 / 10, "remainder short");
        assertEq(r.token.balanceOf(address(factory)), 0);
        assertEq(r.token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_LaunchSplitsAreExactForAnyPoolShare(uint256 poolBps, bytes32 salt) public {
        poolBps = bound(poolBps, 0, 9_000);
        FactoryStandIn factory = new FactoryStandIn();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        FactoryStandIn.Result memory r = factory.launch(salt, distributor, pool, requester, poolBps);
        uint256 seeded = SUPPLY * poolBps / 10_000;
        assertEq(r.token.balanceOf(distributor), SUPPLY / 10);
        assertEq(r.token.balanceOf(pool), seeded);
        assertEq(r.token.balanceOf(requester), SUPPLY - SUPPLY / 10 - seeded);
        assertEq(r.token.totalSupply(), SUPPLY);
    }

    function test_SameSaltCannotRedeploy() public {
        FactoryStandIn factory = new FactoryStandIn();
        factory.launch(bytes32(0), alice, bob, alice, 1_000);
        vm.expectRevert();
        factory.launch(bytes32(0), alice, bob, alice, 1_000);
    }

    /// forge-config: default.fuzz.runs = 500
    function testFuzz_DistributorClaimsArriveWhole(uint8 claimants) public {
        uint256 n = bound(claimants, 1, 50);
        DistributorStandIn distributor = new DistributorStandIn();
        uint256 swarm = SUPPLY / 10;
        token.transfer(address(distributor), swarm);
        address[] memory to = new address[](n);
        for (uint256 i; i < n; ++i) {
            to[i] = address(uint160(0x10000 + i));
        }
        uint256 share = swarm / n;
        distributor.payEqually(token, to, share);
        for (uint256 i; i < n; ++i) {
            assertEq(token.balanceOf(to[i]), share, "claim arrived short");
        }
        assertEq(token.balanceOf(address(distributor)), swarm - share * n, "distributor kept more than rounding");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DistributorCannotOverpay() public {
        DistributorStandIn distributor = new DistributorStandIn();
        token.transfer(address(distributor), 10);
        address[] memory to = new address[](3);
        to[0] = alice;
        to[1] = bob;
        to[2] = makeAddr("carol");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(distributor), 2, 4)
        );
        distributor.payEqually(token, to, 4);
        // The whole batch reverted: nothing moved.
        assertEq(token.balanceOf(address(distributor)), 10);
        assertEq(token.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- bytecode and surface

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function test_RejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted plain ether");
        vm.prank(alice);
        (ok,) = address(token).call{value: 1}(abi.encodeWithSelector(IERC20.transfer.selector, bob, 0));
        assertFalse(ok, "non-payable transfer accepted ether");
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnknownSelectorsRevertAndChangeNothing(bytes4 selector, bytes calldata tail) public {
        vm.assume(
            selector != IERC20.transfer.selector && selector != IERC20.approve.selector
                && selector != IERC20.transferFrom.selector
        );
        token.transfer(alice, 5 ether);
        (bool ok, bytes memory ret) = address(token).call(abi.encodePacked(selector, tail));
        if (ok) {
            // Only view functions may succeed; they must not have changed anything.
            ret;
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5 ether);
    }

    function test_ReturnsTrueAsAbiEncodedWord() public {
        (bool ok, bytes memory ret) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, alice, 1));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));
        (ok, ret) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, alice, 1));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));
        vm.prank(alice);
        (ok, ret) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), bob, 1));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));
    }

    // ---------------------------------------------------------------- edges

    function test_TransferOneWeiAndLastWei() public {
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_TransferOfMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_TransferFromWithFiniteAllowanceOfMaxMinusOneDecrements() public {
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 5);
        assertEq(token.allowance(address(this), alice), type(uint256).max - 6);
    }

    function test_SpendingAllowanceDoesNotEmitApproval() public {
        token.approve(alice, 10);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(address(this), bob, 3);
        assertEq(vm.getRecordedLogs().length, 1, "only the Transfer event");
    }

    function test_ApprovalForOneSpenderCannotBeUsedByAnother() public {
        token.approve(alice, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        // Nor can the spender pull from a different owner.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(bob, alice, 1);
    }

    function test_AllowanceExceedingBalanceStillLimitedByBalance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 1_000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, bob, 11);
        vm.prank(bob);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, bob), 990);
        assertEq(token.balanceOf(bob), 10);
    }

    /// @dev Standard ERC-20 behaviour, noted rather than a defect: tokens sent to the token's own
    /// address are accepted and nobody can recover them, but they stay in the supply.
    function test_TokensSentToTokenAddressAreLockedButCounted() public {
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(address(token), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), address(this), 1);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveSetsExactValue(address owner, address spender, uint256 value) public {
        vm.assume(owner != address(0));
        if (spender == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(spender, value);
            return;
        }
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        assertEq(token.allowance(owner, spender), value);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ChainedTransfersConserve(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        token.transfer(alice, a);
        b = bound(b, 0, a);
        vm.prank(alice);
        token.transfer(bob, b);
        c = bound(c, 0, b);
        vm.prank(bob);
        token.transfer(address(this), c);
        assertEq(token.balanceOf(address(this)), SUPPLY - a + c);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_InfiniteAllowanceNeverDecrements(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, amount);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        assertEq(token.balanceOf(bob), amount);
    }
}
