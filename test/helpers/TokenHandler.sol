// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictIMD} from "../../src/VerdictIMD.sol";

/// @dev Finite actor set and independent balances/allowances model for stateful tests.
contract TokenHandler is Test {
    VerdictIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new VerdictIMD();
        uint256 share = 250_000_000 * 10 ** 18;
        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("invariant actor ", vm.toString(i)));
            actors[i] = actor;
            expectedBalance[actor] = share;
            require(token.transfer(actor, share), "initial distribution failed");
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _transfer(from, to, amount);
    }

    function transferAll(uint8 fromSeed, uint8 toSeed) external {
        address from = actors[fromSeed % actors.length];
        _transfer(from, actors[toSeed % actors.length], expectedBalance[from]);
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Keep revocations, tiny approvals and the finite/infinite boundary reachable.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 choice) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts =
            [uint256(0), 1, expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[choice % amounts.length]);
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maxSpend = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        amount = bound(amount, 0, maxSpend);

        _transferFrom(owner, spender, to, amount);
    }

    function rejectedOverdraw(uint8 fromSeed, uint8 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;
        _reject(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
            )
        );
    }

    /// @dev Rejection must preserve the approval, including when _spendAllowance runs first.
    function rejectedBalanceOverdraw(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint8 toSeed,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                owner,
                expectedBalance[owner],
                amount
            )
        );
    }

    function rejectedAllowanceOverdraw(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint8 toSeed,
        uint256 amount
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = bound(amount, 0, type(uint256).max - 1);
        _approve(owner, spender, approved);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, approved + 1)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1
            )
        );
    }

    function revokeAndReject(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _approve(owner, spender, type(uint256).max);
        _approve(owner, spender, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function spendThenRejectReuse(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, amount);
        _transferFrom(owner, spender, to, amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function rejectedZeroReceiver(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint256 amount,
        bool delegated,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, infinite ? type(uint256).max : amount);
            _reject(
                spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), reason
            );
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), reason);
        }
    }

    function rejectedZeroSpender(uint8 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _reject(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    /// @dev A fee-free round trip restores both balances, even for self/zero transfers.
    function roundTrip(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _transfer(from, to, amount);
        _transfer(to, from, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount, "approval did not replace allowance");
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), expectedBalance[from], "wrong sender debit");
        assertEq(token.balanceOf(to), expectedBalance[to], "wrong recipient credit");
    }

    function _transferFrom(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        assertEq(token.balanceOf(owner), expectedBalance[owner], "wrong delegated debit");
        assertEq(token.balanceOf(to), expectedBalance[to], "wrong delegated credit");
        assertEq(token.allowance(owner, spender), expectedAllowance[owner][spender]);
    }

    /// @dev Catch only the token's revert; a harness assertion must fail the invariant run.
    /// Failed operations never update ghosts. The invariant compares every actor and allowance.
    function _reject(address caller, bytes memory data, bytes memory reason) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, reason, "unexpected revert reason");
    }
}
